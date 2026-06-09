import os
import uuid
import base64
import json
import logging
from datetime import datetime
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException, Depends, Form, Body, UploadFile, File
from core.state import state
from core.config import MODEL_DIR
from core.security import get_current_user
from models.auth import UserPublic

logger = logging.getLogger(__name__)

router = APIRouter()

@router.post("/api/audio/start-stream")
async def start_audio_stream(
    sample_rate: int = Form(16000),
    channels: int = Form(1),
    current_user: UserPublic = Depends(get_current_user)
):
    """Start a new audio recording stream."""
    session_id = str(uuid.uuid4())

    try:
        filename = state.audio_processor.create_audio_stream(
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

@router.websocket("/ws/audio/{session_id}")
async def websocket_audio_stream(websocket: WebSocket, session_id: str):
    """WebSocket endpoint for streaming audio with angle data."""
    await websocket.accept()
    logger.info(
        f"Audio WebSocket connection established for session {session_id}")

    # Auto-create stream if not exists
    if session_id not in state.audio_processor.active_streams:
        state.audio_processor.create_audio_stream(session_id)
        logger.info(f"Auto-created audio stream for session {session_id}")

    try:
        while True:
            message = await websocket.receive()

            if "bytes" in message:
                audio_data = message["bytes"]
                state.audio_processor.write_audio_chunk(session_id, audio_data)
                await websocket.send_json({"status": "received", "bytes": len(audio_data)})

            elif "text" in message:
                try:
                    payload = json.loads(message["text"])

                    if "audio_data" in payload and "angle" in payload:
                        audio_bytes = base64.b64decode(payload["audio_data"])
                        angle = float(payload["angle"])
                        state.audio_processor.write_audio_chunk(
                            session_id, audio_bytes, angle)
                        await websocket.send_json({"status": "received", "angle": angle})

                    elif payload.get("command") == "stop":
                        state.audio_processor.close_audio_stream(session_id)
                        await websocket.send_json({"status": "stopped", "message": "Stream closed"})
                        break

                except json.JSONDecodeError:
                    logger.error("Invalid JSON in audio stream")

    except WebSocketDisconnect:
        logger.info(
            f"Audio WebSocket client disconnected for session {session_id}")
        if session_id in state.audio_processor.active_streams:
            state.audio_processor.close_audio_stream(session_id)
    except Exception as e:
        logger.error(f"Audio WebSocket error: {e}")
        if session_id in state.audio_processor.active_streams:
            state.audio_processor.close_audio_stream(session_id)

@router.post("/api/audio/stop-stream/{session_id}")
async def stop_audio_stream(
    session_id: str,
    current_user: UserPublic = Depends(get_current_user)
):
    """Stop an active audio recording stream."""
    try:
        state.audio_processor.close_audio_stream(session_id)
        return {
            "ok": True,
            "message": "Audio stream stopped successfully"
        }
    except Exception as e:
        logger.error(f"Error stopping audio stream: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/api/audio/recordings")
async def list_audio_recordings(current_user: UserPublic = Depends(get_current_user)):
    """List all audio recordings."""
    try:
        recordings = state.audio_processor.get_audio_files()
        return {
            "ok": True,
            "recordings": recordings,
            "count": len(recordings)
        }
    except Exception as e:
        logger.error(f"Error listing recordings: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/api/audio/active-sessions")
async def get_active_sessions():
    """Get currently active audio recording sessions."""
    try:
        sessions = list(state.audio_processor.active_streams.keys())
        return {
            "ok": True,
            "active_sessions": sessions,
            "count": len(sessions)
        }
    except Exception as e:
        logger.error(f"Error getting active sessions: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/api/audio/angles")
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

@router.post("/api/audio/upload")
async def upload_audio_file(
    file: UploadFile = File(...)
):
    """Upload recorded audio file from frontend and save to MongoDB."""
    try:
        # Read file content for DB persistence
        file_content = await file.read()

        if state.audio_recordings_collection is not None:
            await state.audio_recordings_collection.insert_one({
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

@router.post("/api/audio/set-angle")
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

        if state.audio_angles_collection is not None:
            await state.audio_angles_collection.update_one(
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

@router.get("/api/audio/get-angle")
async def get_current_angle():
    """
    Get the currently tracked angle of the target person.
    If no person is tracked, fallback to the angle previously set via set-angle.
    """
    try:
        logger.info(f"Current target angle: {state.current_target_angle}, distance: {state.current_target_distance}")
        # If a person is actively being tracked, return their real-time angle
        if state.current_target_angle is not None:
            return {
                "ok": True,
                "source": "tracking",
                "angle": round(state.current_target_angle, 2),
                "distance": round(state.current_target_distance, 2)
            }

        # Fallback to the saved angle if no target is actively tracked
        if state.audio_angles_collection is not None:
            saved_angle_doc = await state.audio_angles_collection.find_one({"key": "latest_angle"})
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

@router.get("/api/audio/settings")
async def get_audio_settings():
    """Retrieve all audio settings from MongoDB."""
    try:
        if state.audio_settings_collection is None:
            return {"ok": False, "message": "Database not connected"}

        cursor = state.audio_settings_collection.find({}, {"_id": 0})
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

@router.post("/api/audio/settings")
async def update_audio_settings(
    settings: dict = Body(...)
):
    """Update general audio settings in MongoDB."""
    try:
        if state.audio_settings_collection is None:
            raise HTTPException(
                status_code=503, detail="Database not connected")

        for key, value in settings.items():
            await state.audio_settings_collection.update_one(
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
