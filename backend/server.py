from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
import uvicorn
import cv2
import numpy as np
import base64
import json
import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import threading
import pyvirtualcam

from services.single_tracker import SingleTracker
from services.multi_tracker import MultiTracker

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Executor for CPU-bound tasks
executor = ThreadPoolExecutor(max_workers=1)

# --- OBS and Recording State ---
latest_obs_frame = None  # Store the latest JPEG encoded cropped frame for the OBS feed (deprecated by vcam)
obs_frame_lock = threading.Lock()
is_obs_active = False
vcam = None # Virtual Camera reference
is_recording = False
video_writer = None
recording_filename = ""

# --- Center Stage State (EMA Smoothing) ---
current_cx = 0.5
current_cy = 0.5
current_scale = 1.0

# Configurable parameters for smooth panning
SMOOTHING_FACTOR = 0.1  # Lower is smoother but slower (similar to Dart's TweenAnimation)
TARGET_ASPECT_RATIO = 16.0 / 9.0  # Assuming output is meant to be 16:9 

app = FastAPI(title="AFS Tracking Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize trackers
single_tracker = SingleTracker()
multi_tracker = MultiTracker()

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
    global current_cx, current_cy, current_scale
    
    h, w = frame.shape[:2]
    
    # Defaults
    target_cx = 0.5
    target_cy = 0.5
    target_scale = 1.0
    
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
            
            # Target scale logic (from Dart): max dimension proportion * 1.5 margin
            max_dim = max(box_w / w, box_h / h)
            target_scale = 1.0 / (max_dim * 1.5)
            # Clamp scale
            target_scale = max(1.0, min(target_scale, 3.0))
    else: # single
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
            
            max_dim = max(box_w / w, box_h / h)
            target_scale = 1.0 / (max_dim * 2.0) # slightly tighter for single person
            target_scale = max(1.0, min(target_scale, 3.0))

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
        await asyncio.sleep(0.033) # roughly 30 fps

@app.get("/obs_feed")
async def obs_feed():
    """Endpoint for OBS Media Source to connect to."""
    return StreamingResponse(generate_obs_stream(), media_type="multipart/x-mixed-replace; boundary=frame")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    global is_recording, video_writer, recording_filename, latest_obs_frame, is_obs_active, vcam
    
    await websocket.accept()
    logger.info("New WebSocket connection established.")
    
    current_mode = "single" # Default mode

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
                                logger.info(f"Stopped recording. File saved as {recording_filename}")
                        elif command == "start_obs":
                            if not is_obs_active:
                                is_obs_active = True
                                logger.info("Started OBS Virtual Camera stream")
                                try:
                                    if vcam is None:
                                        vcam = pyvirtualcam.Camera(width=1280, height=720, fps=30)
                                except Exception as e:
                                    logger.error(f"Failed to start vcam: {e}")
                                await websocket.send_json({"type": "obs_ack", "status": "started"})
                        elif command == "stop_obs":
                            if is_obs_active:
                                is_obs_active = False
                                logger.info("Stopped OBS Virtual Camera stream")
                                if vcam is not None:
                                    vcam.close()
                                    vcam = None
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
                    cropped_frame = apply_center_stage_crop(frame, response_data)
                    
                    # 1. Update OBS Virtual Camera
                    if is_obs_active and vcam is not None:
                        try:
                            # Virtual cameras generally strict size requirements
                            cam_frame = cv2.resize(cropped_frame, (vcam.width, vcam.height))
                            cam_frame = cv2.cvtColor(cam_frame, cv2.COLOR_BGR2RGB)
                            vcam.send(cam_frame)
                        except Exception as e:
                            logger.error(f"Failed to push vcam frame: {e}")
                    
                    # 2. Update Recording Output
                    if is_recording:
                        h, w = cropped_frame.shape[:2]
                        if video_writer is None:
                            # Initialize writer with the exact dimensions of the FIRST cropped frame
                            fourcc = cv2.VideoWriter_fourcc(*'avc1')
                            video_writer = cv2.VideoWriter(recording_filename, fourcc, 5.0, (w, h))
                        
                        # Ensure we try to resize cleanly if aspect ratio forces slight off-by-one errors over time
                        if video_writer is not None:
                            target_w = int(video_writer.get(cv2.CAP_PROP_FRAME_WIDTH))
                            target_h = int(video_writer.get(cv2.CAP_PROP_FRAME_HEIGHT))
                            if (w, h) != (target_w, target_h):
                                cropped_frame = cv2.resize(cropped_frame, (target_w, target_h))
                            video_writer.write(cropped_frame)
                except Exception as e:
                    logger.error(f"Error handling post-process crops: {e}")

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected.")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        # Cleanup Virtual Camera
        if vcam is not None:
            vcam.close()
            vcam = None
        is_obs_active = False

        # Cleanup Recording
        if video_writer is not None:
            video_writer.release()
            video_writer = None
        is_recording = False

if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
