import uvicorn
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.state import state
from core.database import connect_db, close_db
from services.syphon import _syphon_stop

# Import Routers
from routers.auth import router as auth_router
from routers.face import router as face_router
from routers.audio import router as audio_router
from routers.video import router as video_router

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="AFS Tracking Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register Routers
app.include_router(auth_router)
app.include_router(face_router)
app.include_router(audio_router)
app.include_router(video_router)

@app.get("/")
async def health_check():
    """Health check endpoint."""
    status_db = "connected" if state.users_collection is not None else "disconnected"
    return {
        "status": "ok",
        "service": "AFS Tracking Backend",
        "mongodb": status_db
    }

@app.on_event("startup")
async def startup_event():
    await connect_db()

@app.on_event("shutdown")
async def shutdown_event():
    _syphon_stop()
    await close_db()

if __name__ == "__main__":
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
