import os
import uuid
import shutil
import pickle
import logging
import asyncio
from datetime import datetime
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from core.state import state
from core.security import (
    normalize_email,
    get_password_hash,
    verify_password,
    create_access_token,
    get_current_user,
    require_users_collection
)
from models.auth import RegisterRequest, LoginRequest, UserPublic, AuthResponse

logger = logging.getLogger(__name__)

router = APIRouter()

@router.post("/register", response_model=AuthResponse)
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

@router.post("/login", response_model=AuthResponse)
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

@router.get("/verify", response_model=UserPublic)
async def verify_token(current_user: UserPublic = Depends(get_current_user)):
    """Verify JWT token and return user info"""
    return current_user

@router.post("/api/enroll_face")
async def enroll_face(
    video: UploadFile = File(...),
    current_user: UserPublic = Depends(get_current_user)
):
    try:
        temp_path = f"temp_enroll_{uuid.uuid4()}.mp4"
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(video.file, buffer)
            
        logger.info(f"Extracting embeddings for user {current_user.id}")
        
        def run_extraction():
            return state.face_service.extract_embeddings_from_video(temp_path)
            
        embeddings, num_frames = await asyncio.get_event_loop().run_in_executor(
            state.executor, run_extraction
        )
        
        pickled_embeddings = pickle.dumps(embeddings)
        await state.users_collection.update_one(
            {"_id": ObjectId(current_user.id)},
            {"$set": {"embeddings": pickled_embeddings}}
        )
        
        os.remove(temp_path)
        
        return {"ok": True, "message": "Face enrolled successfully", "frames_used": num_frames}
    except Exception as e:
        logger.error(f"Enrollment failed: {e}")
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise HTTPException(status_code=500, detail=str(e))
