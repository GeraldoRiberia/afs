import cv2
import pickle
import json
import logging
import asyncio
from datetime import datetime
from bson import ObjectId
from jose import jwt
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from core.state import state
from core.config import SECRET_KEY, ALGORITHM
from services.cropping import decode_binary_image, apply_center_stage_crop
from services.syphon import _syphon_init, _syphon_stop

logger = logging.getLogger(__name__)

router = APIRouter()

async def generate_obs_stream():
    """Generator for the MJPEG stream used by OBS."""
    while True:
        with state.obs_frame_lock:
            if state.latest_obs_frame is not None:
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + state.latest_obs_frame + b'\r\n')
            else:
                # If no frame yet, yield a blank frame or sleep
                await asyncio.sleep(0.1)
                continue
        # Use asyncio sleep to prevent blocking the event loop
        await asyncio.sleep(0.033)  # roughly 30 fps

@router.get("/obs_feed")
async def obs_feed():
    """Endpoint for OBS Media Source to connect to."""
    return StreamingResponse(generate_obs_stream(), media_type="multipart/x-mixed-replace; boundary=frame")

@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    logger.info("New WebSocket connection established.")

    current_mode = "single"  # Default mode
    ws_user_embeddings = None

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
                    elif "type" in payload and payload["type"] == "auth":
                        token = payload.get("token")
                        try:
                            token_data = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
                            user_id = token_data.get("sub")
                            if user_id:
                                user = await state.users_collection.find_one({"_id": ObjectId(user_id)})
                                if user and "embeddings" in user and user["embeddings"]:
                                    ws_user_embeddings = pickle.loads(user["embeddings"])
                                    logger.info(f"Loaded custom face embeddings for user {user_id}")
                                    await websocket.send_json({"type": "auth_ack", "status": "enrolled"})
                                else:
                                    await websocket.send_json({"type": "auth_ack", "status": "no_enrollment"})
                        except Exception as e:
                            logger.error(f"WS Auth failed: {e}")
                    elif "zoom_scale" in payload:
                        state.zoom_multiplier = float(payload["zoom_scale"])
                        logger.info(f"Updated zoom multiplier to {state.zoom_multiplier}")
                    elif "command" in payload:
                        # Handle recording commands
                        command = payload["command"]
                        if command == "start_recording":
                            if not state.is_recording:
                                state.is_recording = True
                                state.recording_filename = f"capture_{datetime.now().strftime('%Y%m%d_%H%M%S')}.mp4"
                                logger.info(f"Started recording to {state.recording_filename}")
                                await websocket.send_json({"type": "recording_ack", "status": "started"})
                        elif command == "stop_recording":
                            if state.is_recording:
                                state.is_recording = False
                                if state.video_writer is not None:
                                    state.video_writer.release()
                                    state.video_writer = None
                                logger.info(f"Stopped recording. File saved as {state.recording_filename}")
                        elif command == "start_obs":
                            if not state.is_obs_active:
                                state.is_obs_active = True
                                logger.info("Started OBS MJPEG stream")
                                await websocket.send_json({"type": "obs_ack", "status": "started"})
                        elif command == "stop_obs":
                            if state.is_obs_active:
                                state.is_obs_active = False
                                logger.info("Stopped OBS MJPEG stream")
                                await websocket.send_json({"type": "obs_ack", "status": "stopped"})
                        elif command == "start_syphon":
                            # Accept optional camera index (default 0)
                            camera_idx = int(payload.get("camera_idx", 0))
                            if not state.is_syphon_active:
                                ok = await asyncio.get_event_loop().run_in_executor(
                                    state.executor, _syphon_init, camera_idx
                                )
                                if ok:
                                    state.is_syphon_active = True
                                    logger.info(f"Syphon virtual camera started (camera {camera_idx}).")
                                    await websocket.send_json({"type": "syphon_ack", "status": "started"})
                                else:
                                    await websocket.send_json({
                                        "type": "syphon_ack",
                                        "status": "error",
                                        "message": "syphon-python not installed, Metal unavailable, or camera could not be opened."
                                    })
                        elif command == "stop_syphon":
                            if state.is_syphon_active:
                                await asyncio.get_event_loop().run_in_executor(
                                    state.executor, _syphon_stop
                                )
                                logger.info("Syphon virtual camera stopped.")
                                await websocket.send_json({"type": "syphon_ack", "status": "stopped"})
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
                def run_inference(f, mode, embeddings=None):
                    if mode == "single":
                        return state.single_tracker.process_frame(f, custom_embeddings=embeddings)
                    elif mode == "multi":
                        return state.multi_tracker.process_frame(f)
                    else:
                        return {"error": f"Unknown mode: {mode}"}

                # Process Frame in executor
                response_data = {}
                try:
                    response_data = await asyncio.get_event_loop().run_in_executor(
                        state.executor, run_inference, frame, current_mode, ws_user_embeddings
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

                    # 1. Update OBS MJPEG Feed
                    if state.is_obs_active:
                        ret, buffer = cv2.imencode('.jpg', cropped_frame)
                        if ret:
                            with state.obs_frame_lock:
                                state.latest_obs_frame = buffer.tobytes()

                    # 2. WebSocket frames no longer drive the Syphon feed.
                    # The SyphonDirectCapture thread reads the camera at 30 fps
                    # and applies the EMA crop state independently.

                    # 3. Update Recording Output
                    if state.is_recording:
                        h, w = cropped_frame.shape[:2]
                        if state.video_writer is None:
                            # Initialize writer with the exact dimensions of the FIRST cropped frame
                            fourcc = cv2.VideoWriter_fourcc(*'avc1')
                            state.video_writer = cv2.VideoWriter(
                                state.recording_filename, fourcc, 5.0, (w, h))

                        # Ensure we try to resize cleanly if aspect ratio forces slight off-by-one errors over time
                        if state.video_writer is not None:
                            target_w = int(state.video_writer.get(cv2.CAP_PROP_FRAME_WIDTH))
                            target_h = int(state.video_writer.get(cv2.CAP_PROP_FRAME_HEIGHT))
                            if (w, h) != (target_w, target_h):
                                cropped_frame = cv2.resize(cropped_frame, (target_w, target_h))
                            state.video_writer.write(cropped_frame)
                except Exception as e:
                    logger.error(f"Error handling post-process crops: {e}")

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected.")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        state.is_obs_active = False
        state.is_syphon_active = False

        # Cleanup Recording
        if state.video_writer is not None:
            state.video_writer.release()
            state.video_writer = None
        state.is_recording = False
