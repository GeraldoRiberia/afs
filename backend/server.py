from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, status, Depends, UploadFile, File, Form, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import uvicorn
import cv2
import numpy as np
import json
import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
import threading
import os
import base64
import hashlib
import math
from pydantic import BaseModel, Field
from pymongo import AsyncMongoClient
import bcrypt
from jose import JWTError, jwt
from dotenv import load_dotenv
from pathlib import Path
import shutil
import uuid

from services.single_tracker import SingleTracker
from services.multi_tracker import MultiTracker
from services.face_recognition import FaceRecognitionService
from services.audio_processing import AudioProcessor

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Executor for CPU-bound tasks
executor = ThreadPoolExecutor(max_workers=1)

# --- OBS and Recording State ---
latest_obs_frame = None  # Store the latest JPEG encoded cropped frame for the OBS feed
obs_frame_lock = threading.Lock()
is_obs_active = False
is_recording = False
video_writer = None
recording_filename = ""

# --- Center Stage State (EMA Smoothing) ---
current_cx = 0.5
current_cy = 0.5
current_scale = 1.0
zoom_multiplier = 1.0

# --- Real-time Target Tracking State ---
current_target_angle = None
current_target_distance = None

# Configurable parameters for smooth panning
# Lower is smoother but slower (similar to Dart's TweenAnimation)
SMOOTHING_FACTOR = 0.1
TARGET_ASPECT_RATIO = 16.0 / 9.0  # Assuming output is meant to be 16:9

app = FastAPI(title="AFS Tracking Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize trackers and services
MODEL_DIR = Path(__file__).parent / "Model"
single_tracker = SingleTracker()
multi_tracker = MultiTracker()
face_service = FaceRecognitionService(str(MODEL_DIR))
audio_processor = AudioProcessor(str(MODEL_DIR))

# MongoDB state
mongo_client: AsyncMongoClient | None = None
users_collection = None
audio_recordings_collection = None
audio_settings_collection = None
audio_angles_collection = None



# JWT Configuration
SECRET_KEY = os.getenv(
    "JWT_SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

security = HTTPBearer()


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=80)
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=8, max_length=128)


class UserPublic(BaseModel):
    id: str
    full_name: str
    email: str


class AuthResponse(BaseModel):
    ok: bool
    message: str
    user: UserPublic
    token: str


def normalize_email(email: str) -> str:
    return email.strip().lower()


def get_password_hash(password: str) -> str:
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))


def require_users_collection():
    if users_collection is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is not initialized yet. Please retry.",
        )
    return users_collection


def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    collection = require_users_collection()
    token = credentials.credentials

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials",
            )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )

    from bson import ObjectId
    try:
        user_doc = await collection.find_one({"_id": ObjectId(user_id)})
    except:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    if user_doc is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    return UserPublic(
        id=str(user_doc["_id"]),
        full_name=user_doc["full_name"],
        email=user_doc["email"],
    )


def decode_binary_image(img_data: bytes):
    """Decodes raw JPEG bytes into an OpenCV numpy array."""
    try:
        nparr = np.frombuffer(img_data, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        return img
    except Exception as e:
        logger.error(f"Failed to decode image: {e}")
        return None


def apply_center_stage_crop(frame, tracking_data):
    """
    Applies an exponential moving average (EMA) to smoothly pan and zoom
    the frame based on the tracking target bounding box.
    Returns the cropped frame.
    """
    global current_cx, current_cy, current_scale, current_target_angle, current_target_distance, zoom_multiplier

    h, w = frame.shape[:2]

    # Defaults
    target_cx = 0.5
    target_cy = 0.5
    target_scale = 1.0

    target_found = False

    # Calculate target state based on tracking data
    boxes = tracking_data.get("boxes", [])
    if tracking_data.get("mode") == "multi":
        if "aggregate_box" in tracking_data:
            ab = tracking_data["aggregate_box"]
            box_cx = (ab["x1"] + ab["x2"]) / 2.0
            box_cy = (ab["y1"] + ab["y2"]) / 2.0
            box_w = ab["x2"] - ab["x1"]
            box_h = ab["y2"] - ab["y1"]

            target_cx = box_cx / w
            target_cy = box_cy / h
            target_found = True

            # Target scale logic (from Dart): max dimension proportion * 1.5 margin
            max_dim = max(box_w / w, box_h / h)
            target_scale = 1.0 / (max_dim * 1.5)
            # Clamp scale
            target_scale = max(1.0, min(target_scale, 3.0))
    else:  # single
        target_box = None
        for b in boxes:
            if b.get("is_target"):
                target_box = b
                break

        if target_box:
            box_cx = (target_box["x1"] + target_box["x2"]) / 2.0
            box_cy = (target_box["y1"] + target_box["y2"]) / 2.0
            box_w = target_box["x2"] - target_box["x1"]
            box_h = target_box["y2"] - target_box["y1"]

            target_cx = box_cx / w
            target_cy = box_cy / h
            target_found = True

            max_dim = max(box_w / w, box_h / h)
            # slightly tighter for single person
            target_scale = 1.0 / (max_dim * 2.0)
            target_scale = max(1.0, min(target_scale, 3.0))

    if target_found:
        # Apply user zoom multiplier
        target_scale = max(1.0, min(target_scale * zoom_multiplier, 10.0))

        # Calculate distance and angle from the frame center (w/2, h/2) to the target bounding box center (box_cx, box_cy)
        center_x, center_y = w / 2.0, h / 2.0

        dx = box_cx - center_x
        dy = box_cy - center_y

        current_target_distance = math.hypot(dx, dy)
        # Convert atan2 result to 0-360 degrees
        angle = math.degrees(math.atan2(dy, dx))
        current_target_angle = angle % 360.0
    else:
        current_target_angle = None
        current_target_distance = None

    # Apply EMA smoothing
    current_cx += (target_cx - current_cx) * SMOOTHING_FACTOR
    current_cy += (target_cy - current_cy) * SMOOTHING_FACTOR
    current_scale += (target_scale - current_scale) * SMOOTHING_FACTOR

    # Calculate crop dimensions
    # When scale is S, the crop width is w / S
    crop_w = int(w / current_scale)
    crop_h = int(h / current_scale)

    # Enforce aspect ratio
    # If crop_w / crop_h is not 16:9, adjust one to match
    current_ar = crop_w / max(1, crop_h)
    if current_ar > TARGET_ASPECT_RATIO:
        # Too wide, shrink width
        crop_w = int(crop_h * TARGET_ASPECT_RATIO)
    else:
        # Too tall, shrink height
        crop_h = int(crop_w / TARGET_ASPECT_RATIO)

    # Calculate top-left point of crop, clamping to frame boundaries
    center_px_x = int(current_cx * w)
    center_px_y = int(current_cy * h)

    start_x = max(0, center_px_x - crop_w // 2)
    start_y = max(0, center_px_y - crop_h // 2)

    # Adjust if crop box goes out of bounds
    if start_x + crop_w > w:
        start_x = w - crop_w
    if start_y + crop_h > h:
        start_y = h - crop_h

    # Crop
    cropped = frame[start_y:start_y+crop_h, start_x:start_x+crop_w]
    return cropped


async def generate_obs_stream():
    """Generator for the MJPEG stream used by OBS."""
    global latest_obs_frame
    while True:
        with obs_frame_lock:
            if latest_obs_frame is not None:
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + latest_obs_frame + b'\r\n')
            else:
                # If no frame yet, yield a blank frame or sleep
                await asyncio.sleep(0.1)
                continue
        # Use asyncio sleep to prevent blocking the event loop
        await asyncio.sleep(0.033)  # roughly 30 fps


@app.get("/obs_feed")
async def obs_feed():
    """Endpoint for OBS Media Source to connect to."""
    return StreamingResponse(generate_obs_stream(), media_type="multipart/x-mixed-replace; boundary=frame")


async def vcam_generator_loop():
    """Background task to push frames to the virtual camera at 30fps."""
    global is_obs_active, vcam, latest_vcam_frame
    while True:
        try:
            if is_obs_active and vcam is not None and latest_vcam_frame is not None:
                vcam.send(latest_vcam_frame)
        except Exception as e:
            logger.error(f"vcam loop error: {e}")
        await asyncio.sleep(1/30)


@app.get("/")
async def health_check():
    """Health check endpoint."""
    status_db = "connected" if users_collection is not None else "disconnected"
    return {
        "status": "ok",
        "service": "AFS Tracking Backend",
        "mongodb": status_db
    }


async def mongodb_reconnect_loop():
    """Background task to attempt MongoDB reconnection if disconnected."""
    global mongo_client, users_collection, audio_recordings_collection, audio_settings_collection
    while True:
        if users_collection is None:
            mongo_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
            mongo_db_name = os.getenv("MONGODB_DB", "afs")
            try:
                logger.info("Attempting to reconnect to MongoDB...")
                client = AsyncMongoClient(
                    mongo_uri, serverSelectionTimeoutMS=5000)
                # Ping to force connection verification
                await client.admin.command('ping')

                # Re-initialize
                mongo_client = client
                db = mongo_client[mongo_db_name]
                users_collection = db["users"]
                audio_recordings_collection = db["audio_recordings"]
                audio_settings_collection = db["audio_settings"]
                audio_angles_collection = db["audio_angles"]

                await users_collection.create_index("email", unique=True)
                logger.info("Successfully reconnected to MongoDB.")
            except Exception as e:
                logger.error(f"MongoDB reconnection failed: {e}")
                mongo_client = None
                users_collection = None
                audio_recordings_collection = None
                audio_settings_collection = None
                audio_angles_collection = None

        # Wait before next check (e.g., 10 seconds)
        await asyncio.sleep(10)


@app.on_event("startup")
async def startup_event():
    global mongo_client, users_collection, audio_recordings_collection, audio_settings_collection, audio_angles_collection
    mongo_uri = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
    mongo_db_name = os.getenv("MONGODB_DB", "afs")

    try:
        mongo_client = AsyncMongoClient(
            mongo_uri, serverSelectionTimeoutMS=5000)
        # Ping to force connection verification
        await mongo_client.admin.command('ping')

        db = mongo_client[mongo_db_name]
        users_collection = db["users"]
        audio_recordings_collection = db["audio_recordings"]
        audio_settings_collection = db["audio_settings"]
        audio_angles_collection = db["audio_angles"]

        await users_collection.create_index("email", unique=True)
        logger.info("Connected to MongoDB and initialized collections.")
    except Exception as e:
        logger.warning(f"MongoDB connection failed on startup: {e}. Starting reconnection loop.")
        mongo_client = None
        users_collection = None
        audio_recordings_collection = None
        audio_settings_collection = None
        audio_angles_collection = None

    asyncio.create_task(vcam_generator_loop())
    asyncio.create_task(mongodb_reconnect_loop())


@app.on_event("shutdown")
async def shutdown_event():
    global mongo_client
    if mongo_client is not None:
        mongo_client.close()
        logger.info("MongoDB connection closed.")


@app.post("/auth/register", response_model=AuthResponse)
async def register(payload: RegisterRequest):
    collection = require_users_collection()
    email = normalize_email(payload.email)

    existing_user = await collection.find_one({"email": email})
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        )

    now = datetime.utcnow()
    user_doc = {
        "full_name": payload.full_name.strip(),
        "email": email,
        "password_hash": get_password_hash(payload.password),
        "created_at": now,
        "updated_at": now,
    }
    insert_result = await collection.insert_one(user_doc)

    user_id = str(insert_result.inserted_id)
    access_token = create_access_token(data={"sub": user_id})

    return AuthResponse(
        ok=True,
        message="Account created successfully.",
        user=UserPublic(
            id=user_id,
            full_name=user_doc["full_name"],
            email=user_doc["email"],
        ),
        token=access_token,
    )


@app.post("/auth/login", response_model=AuthResponse)
async def login(payload: LoginRequest):
    collection = require_users_collection()
    email = normalize_email(payload.email)

    user_doc = await collection.find_one({"email": email})
    if not user_doc or not verify_password(payload.password, user_doc["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
        )

    user_id = str(user_doc["_id"])
    access_token = create_access_token(data={"sub": user_id})

    return AuthResponse(
        ok=True,
        message="Login successful.",
        user=UserPublic(
            id=user_id,
            full_name=user_doc["full_name"],
            email=user_doc["email"],
        ),
        token=access_token,
    )


@app.get("/auth/verify", response_model=UserPublic)
async def verify_token(current_user: UserPublic = Depends(get_current_user)):
    """Verify JWT token and return user info"""
    return current_user


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    global is_recording, video_writer, recording_filename, latest_obs_frame, is_obs_active, zoom_multiplier

    await websocket.accept()
    logger.info("New WebSocket connection established.")

    current_mode = "single"  # Default mode

    try:
        while True:
            # Receive message (either text JSON or binary frame)
            message = await websocket.receive()

            if "text" in message:
                try:
                    payload = json.loads(message["text"])
                    if "mode" in payload and payload["mode"] != current_mode:
                        logger.info(f"Switching mode from {current_mode} to {payload['mode']}")
                        current_mode = payload["mode"]
                        await websocket.send_json({"type": "mode_ack", "mode": current_mode})
                    elif "zoom_scale" in payload:
                        zoom_multiplier = float(payload["zoom_scale"])
                        logger.info(f"Updated zoom multiplier to {zoom_multiplier}")
                    elif "command" in payload:
                        # Handle recording commands
                        command = payload["command"]
                        if command == "start_recording":
                            if not is_recording:
                                is_recording = True
                                recording_filename = f"capture_{datetime.now().strftime('%Y%m%d_%H%M%S')}.mp4"
                                logger.info(f"Started recording to {recording_filename}")
                                await websocket.send_json({"type": "recording_ack", "status": "started"})
                        elif command == "stop_recording":
                            if is_recording:
                                is_recording = False
                                if video_writer is not None:
                                    video_writer.release()
                                    video_writer = None
                                logger.info(f'''Stopped recording. File saved as {recording_filename}''')
                        elif command == "start_obs":
                            if not is_obs_active:
                                is_obs_active = True
                                logger.info("Started OBS MJPEG stream")
                                await websocket.send_json({"type": "obs_ack", "status": "started"})
                        elif command == "stop_obs":
                            if is_obs_active:
                                is_obs_active = False
                                logger.info("Stopped OBS MJPEG stream")
                                await websocket.send_json({"type": "obs_ack", "status": "stopped"})
                except json.JSONDecodeError:
                    logger.error("Invalid JSON received.")
                continue

            elif "bytes" in message:
                frame_data = message["bytes"]
                frame = decode_binary_image(frame_data)

                if frame is None:
                    await websocket.send_json({"error": "Failed to decode binary frame"})
                    continue

                # Prepare inference function
                def run_inference(f, mode):
                    if mode == "single":
                        return single_tracker.process_frame(f)
                    elif mode == "multi":
                        return multi_tracker.process_frame(f)
                    else:
                        return {"error": f"Unknown mode: {mode}"}

                # Process Frame in executor
                response_data = {}
                try:
                    response_data = await asyncio.get_event_loop().run_in_executor(
                        executor, run_inference, frame, current_mode
                    )
                except Exception as e:
                    logger.error(f"Error processing frame in {current_mode} mode: {e}")
                    response_data = {"error": str(e)}

                # Send results back to client
                response_data["mode"] = current_mode
                await websocket.send_json(response_data)

                # Apply Crop and Handle OBS / Recording
                try:
                    cropped_frame = apply_center_stage_crop(
                        frame, response_data)

                    # 1. Update OBS Feed
                    if is_obs_active:
                        ret, buffer = cv2.imencode('.jpg', cropped_frame)
                        if ret:
                            with obs_frame_lock:
                                latest_obs_frame = buffer.tobytes()

                    # 2. Update Recording Output
                    if is_recording:
                        h, w = cropped_frame.shape[:2]
                        if video_writer is None:
                            # Initialize writer with the exact dimensions of the FIRST cropped frame
                            fourcc = cv2.VideoWriter_fourcc(*'avc1')
                            video_writer = cv2.VideoWriter(
                                recording_filename, fourcc, 5.0, (w, h))

                        # Ensure we try to resize cleanly if aspect ratio forces slight off-by-one errors over time
                        if video_writer is not None:
                            target_w = int(video_writer.get(
                                cv2.CAP_PROP_FRAME_WIDTH))
                            target_h = int(video_writer.get(
                                cv2.CAP_PROP_FRAME_HEIGHT))
                            if (w, h) != (target_w, target_h):
                                cropped_frame = cv2.resize(
                                    cropped_frame, (target_w, target_h))
                            video_writer.write(cropped_frame)
                except Exception as e:
                    logger.error(f"Error handling post-process crops: {e}")

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected.")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        is_obs_active = False

        # Cleanup Recording
        if video_writer is not None:
            video_writer.release()
            video_writer = None
        is_recording = False

# === FACE RECOGNITION ENDPOINTS ===


@app.post("/api/face/upload-video")
async def upload_reference_video(
    file: UploadFile = File(...),
    current_user: UserPublic = Depends(get_current_user)
):
    """Upload a 360-degree reference video for face recognition training."""
    if not file.filename.endswith(('.mp4', '.avi', '.mov', '.mkv')):
        raise HTTPException(
            status_code=400, detail="Invalid video format. Use mp4, avi, mov, or mkv")

    video_path = MODEL_DIR / "my_scan.mp4"

    try:
        with open(video_path, 'wb') as f:
            shutil.copyfileobj(file.file, f)

        embeddings, num_frames = await asyncio.get_event_loop().run_in_executor(
            executor, face_service.extract_embeddings_from_video, str(
                video_path)
        )

        face_service.save_embeddings_cache(
            embeddings, str(video_path), num_frames)

        return {
            "ok": True,
            "message": "Video processed successfully",
            "frames_used": num_frames,
            "embeddings_count": len(embeddings)
        }
    except Exception as e:
        logger.error(f"Error processing video: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/face/upload-image")
async def upload_reference_image(
    file: UploadFile = File(...),
    current_user: UserPublic = Depends(get_current_user)
):
    """Upload a reference image for face recognition."""
    if not file.filename.endswith(('.jpg', '.jpeg', '.png')):
        raise HTTPException(
            status_code=400, detail="Invalid image format. Use jpg, jpeg, or png")

    image_path = MODEL_DIR / f"ref_{file.filename}"

    try:
        with open(image_path, 'wb') as f:
            shutil.copyfileobj(file.file, f)

        embeddings = await asyncio.get_event_loop().run_in_executor(
            executor, face_service.extract_embeddings_from_image, str(
                image_path)
        )

        return {
            "ok": True,
            "message": "Image processed successfully",
            "embeddings_count": len(embeddings),
            "saved_path": str(image_path)
        }
    except Exception as e:
        logger.error(f"Error processing image: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/face/cache-status")
async def get_cache_status(current_user: UserPublic = Depends(get_current_user)):
    """Get the current face recognition cache status."""
    cache_data = face_service.load_embeddings_cache()

    if cache_data:
        return {
            "ok": True,
            "cached": True,
            "video_path": cache_data.get('video_path'),
            "model_name": cache_data.get('model_name'),
            "num_frames_used": cache_data.get('num_frames_used'),
            "version": cache_data.get('version')
        }
    else:
        return {
            "ok": True,
            "cached": False,
            "message": "No cache found. Please upload a reference video or image."
        }

# === AUDIO STREAMING ENDPOINTS ===


@app.post("/api/audio/start-stream")
async def start_audio_stream(
    sample_rate: int = Form(16000),
    channels: int = Form(1),
    current_user: UserPublic = Depends(get_current_user)
):
    """Start a new audio recording stream."""
    session_id = str(uuid.uuid4())

    try:
        filename = audio_processor.create_audio_stream(
            session_id, sample_rate, channels)
        return {
            "ok": True,
            "session_id": session_id,
            "filename": filename,
            "sample_rate": sample_rate,
            "channels": channels
        }
    except Exception as e:
        logger.error(f"Error starting audio stream: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.websocket("/ws/audio/{session_id}")
async def websocket_audio_stream(websocket: WebSocket, session_id: str):
    """WebSocket endpoint for streaming audio with angle data."""
    await websocket.accept()
    logger.info(
        f"Audio WebSocket connection established for session {session_id}")

    # Auto-create stream if not exists
    if session_id not in audio_processor.active_streams:
        audio_processor.create_audio_stream(session_id)
        logger.info(f"Auto-created audio stream for session {session_id}")

    try:
        while True:
            message = await websocket.receive()

            if "bytes" in message:
                audio_data = message["bytes"]
                audio_processor.write_audio_chunk(session_id, audio_data)
                await websocket.send_json({"status": "received", "bytes": len(audio_data)})

            elif "text" in message:
                try:
                    payload = json.loads(message["text"])

                    if "audio_data" in payload and "angle" in payload:
                        audio_bytes = base64.b64decode(payload["audio_data"])
                        angle = float(payload["angle"])
                        audio_processor.write_audio_chunk(
                            session_id, audio_bytes, angle)
                        await websocket.send_json({"status": "received", "angle": angle})

                    elif payload.get("command") == "stop":
                        audio_processor.close_audio_stream(session_id)
                        await websocket.send_json({"status": "stopped", "message": "Stream closed"})
                        break

                except json.JSONDecodeError:
                    logger.error("Invalid JSON in audio stream")

    except WebSocketDisconnect:
        logger.info(
            f"Audio WebSocket client disconnected for session {session_id}")
        if session_id in audio_processor.active_streams:
            audio_processor.close_audio_stream(session_id)
    except Exception as e:
        logger.error(f"Audio WebSocket error: {e}")
        if session_id in audio_processor.active_streams:
            audio_processor.close_audio_stream(session_id)


@app.post("/api/audio/stop-stream/{session_id}")
async def stop_audio_stream(
    session_id: str,
    current_user: UserPublic = Depends(get_current_user)
):
    """Stop an active audio recording stream."""
    try:
        audio_processor.close_audio_stream(session_id)
        return {
            "ok": True,
            "message": "Audio stream stopped successfully"
        }
    except Exception as e:
        logger.error(f"Error stopping audio stream: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/audio/recordings")
async def list_audio_recordings(current_user: UserPublic = Depends(get_current_user)):
    """List all audio recordings."""
    try:
        recordings = audio_processor.get_audio_files()
        return {
            "ok": True,
            "recordings": recordings,
            "count": len(recordings)
        }
    except Exception as e:
        logger.error(f"Error listing recordings: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/audio/active-sessions")
async def get_active_sessions():
    """Get currently active audio recording sessions."""
    try:
        sessions = list(audio_processor.active_streams.keys())
        return {
            "ok": True,
            "active_sessions": sessions,
            "count": len(sessions)
        }
    except Exception as e:
        logger.error(f"Error getting active sessions: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/audio/angles")
async def get_audio_angles():
    """Get angle metadata for the latest audio session."""
    try:
        audio_dir = MODEL_DIR / "audio_recordings"
        metadata_files = list(audio_dir.glob("*_metadata.txt"))

        if not metadata_files:
            raise HTTPException(
                status_code=404,
                detail="No metadata found"
            )

        # Get the most recently modified metadata file
        import os
        metadata_file = max(metadata_files, key=os.path.getmtime)

        angles_data = []
        with open(metadata_file, 'r') as f:
            lines = f.readlines()
            # Skip header if present
            start_idx = 1 if lines and 'timestamp' in lines[0] else 0
            for line in lines[start_idx:]:
                if line.strip():
                    parts = line.strip().split(',')
                    if len(parts) >= 2:
                        try:
                            timestamp = float(parts[0])
                            angle = float(parts[1])
                            angles_data.append(
                                {"timestamp": timestamp, "angle": angle})
                        except ValueError:
                            continue

        return {
            "ok": True,
            "file": metadata_file.name,
            "angles": angles_data,
            "count": len(angles_data)
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error retrieving angles: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/audio/upload")
async def upload_audio_file(
    file: UploadFile = File(...)
):
    """Upload recorded audio file from frontend and save to MongoDB."""
    try:
        # Read file content for DB persistence
        file_content = await file.read()

        if audio_recordings_collection is not None:
            await audio_recordings_collection.insert_one({
                "filename": file.filename,
                "content": file_content,  # Saved as binary in MongoDB
                "content_type": file.content_type,
                "timestamp": datetime.utcnow()
            })

        return {
            "ok": True,
            "message": "Audio file saved to database successfully",
            "filename": file.filename,
            "size": len(file_content)
        }
    except Exception as e:
        logger.error(f"Error saving audio to DB: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/audio/set-angle")
async def set_desired_angle(
    angle: float = Form(...)
):
    """Send a desired angle to the audio processing system and persist to MongoDB."""
    try:
        if not (0 <= angle <= 360):
            raise HTTPException(
                status_code=400,
                detail="Angle must be between 0 and 360 degrees"
            )

        if audio_angles_collection is not None:
            await audio_angles_collection.update_one(
                {"key": "latest_angle"},
                {"$set": {"value": angle, "updated_at": datetime.utcnow()}},
                upsert=True
            )

        logger.info(f"Set and persisted desired angle {angle}° to DB")

        return {
            "ok": True,
            "message": f"Desired angle set to {angle}° and saved to DB",
            "angle": angle
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error setting angle in DB: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/audio/get-angle")
async def get_current_angle():
    """
    Get the currently tracked angle of the target person.
    If no person is tracked, fallback to the angle previously set via set-angle.
    """
    try:
        global current_target_angle, current_target_distance

        logger.info(current_target_angle, current_target_distance)
        # If a person is actively being tracked, return their real-time angle
        if current_target_angle is not None:
            return {
                "ok": True,
                "source": "tracking",
                "angle": round(current_target_angle, 2),
                "distance": round(current_target_distance, 2)
            }

        # Fallback to the saved angle if no target is actively tracked
        if audio_angles_collection is not None:
            saved_angle_doc = await audio_angles_collection.find_one({"key": "latest_angle"})
            if saved_angle_doc and "value" in saved_angle_doc:
                return {
                    "ok": True,
                    "source": "database",
                    "angle": float(saved_angle_doc["value"]),
                    "distance": None
                }

        return {
            "ok": False,
            "message": "No active tracking and no saved angle found",
            "angle": None,
            "distance": None
        }
    except Exception as e:
        logger.error(f"Error retrieving angle: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/audio/settings")
async def get_audio_settings():
    """Retrieve all audio settings from MongoDB."""
    try:
        if audio_settings_collection is None:
            return {"ok": False, "message": "Database not connected"}

        cursor = audio_settings_collection.find({}, {"_id": 0})
        settings_list = await cursor.to_list(length=100)

        # Convert list to dictionary
        settings_dict = {s["key"]: s["value"]
                         for s in settings_list if "key" in s}

        return {
            "ok": True,
            "settings": settings_dict
        }
    except Exception as e:
        logger.error(f"Error retrieving audio settings: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/audio/settings")
async def update_audio_settings(
    settings: dict = Body(...)
):
    """Update general audio settings in MongoDB."""
    try:
        if audio_settings_collection is None:
            raise HTTPException(
                status_code=503, detail="Database not connected")

        for key, value in settings.items():
            await audio_settings_collection.update_one(
                {"key": key},
                {"$set": {"value": value, "updated_at": datetime.utcnow()}},
                upsert=True
            )

        return {
            "ok": True,
            "message": "Audio settings updated successfully",
            "updated_keys": list(settings.keys())
        }
    except Exception as e:
        logger.error(f"Error updating audio settings: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
