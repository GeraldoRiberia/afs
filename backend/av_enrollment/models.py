from pydantic import BaseModel
from typing import Optional, List, Tuple
from enum import Enum

class EnrollmentStatus(str, Enum):
    IDLE = "idle"
    WAITING_SPEECH = "waiting_speech"
    VERIFYING_SPEAKER_COUNT = "verifying_speaker_count"
    BUILDING_PATH = "building_path"
    ENROLLING = "enrolling"
    ENROLLED = "enrolled"
    FAILED = "failed"

class AudioVisualPath(BaseModel):
    timestamps: List[float]
    visual_angles: List[float]   # degrees, from face bounding box
    audio_angles: List[float]    # degrees, from SRP‑PHAT
    rms_energy: List[float]      # from audio
    mar_values: List[float]      # mouth aspect ratio per frame

class EnrollmentSession(BaseModel):
    face_track_id: int
    visual_path: AudioVisualPath = None
    correlation_score: float = None
    clean_audio_buffer: bytes = None
    voice_embedding: List[float] = None
    status: EnrollmentStatus = EnrollmentStatus.IDLE
