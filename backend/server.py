from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import cv2
import numpy as np
import base64
import json
import logging
import asyncio
from concurrent.futures import ThreadPoolExecutor

from services.single_tracker import SingleTracker
from services.multi_tracker import MultiTracker

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Executor for CPU-bound tasks
executor = ThreadPoolExecutor(max_workers=1)

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

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
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

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected.")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")

if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
