import shutil
import logging
import asyncio
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from core.state import state
from core.config import MODEL_DIR
from core.security import get_current_user
from models.auth import UserPublic

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/face")

@router.post("/upload-video")
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
            state.executor, state.face_service.extract_embeddings_from_video, str(video_path)
        )

        state.face_service.save_embeddings_cache(
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

@router.post("/upload-image")
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
            state.executor, state.face_service.extract_embeddings_from_image, str(image_path)
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

@router.get("/cache-status")
async def get_cache_status(current_user: UserPublic = Depends(get_current_user)):
    """Get the current face recognition cache status."""
    cache_data = state.face_service.load_embeddings_cache()

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
