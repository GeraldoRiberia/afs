import os
from pathlib import Path


class AVConfig:
    # Model paths (adjust to your actual locations)
    MODEL_DIR = Path(__file__).parent.parent / "Model"

    # Cobra VAD
    COBRA_ACCESS_KEY = os.getenv("PICOVOICE_ACCESS_KEY", "")
    COBRA_MODEL_PATH = str(MODEL_DIR / "cobra_model.pv")

    # Falcon OSD
    FALCON_MODEL_PATH = str(MODEL_DIR / "falcon_model.pv")

    # SpeechBrain ECAPA-TDNN (will download on first use)
    SPEECHBRAIN_MODEL = "speechbrain/spkrec-ecapa-voxceleb"

    # DeepFilterNet
    DEEPFILTER_MODEL = "deepfilter/DeepFilterNet2"

    # SRP-PHAT parameters
    SAMPLE_RATE = 16000
    MIC_DISTANCE_M = 0.15      # distance between stereo microphones (adjust)
    SPEED_OF_SOUND_MPS = 343.0

    # Path correlation
    DTW_WINDOW_SEC = 1.5       # 1.5 seconds window for alignment
    ANGLE_TOLERANCE_DEG = 5.0
    CORRELATION_THRESHOLD = 0.9

    # Enrollment
    MIN_CLEAN_SPEECH_SEC = 1.5
    MAX_ENROLL_SEC = 2.0
    COSINE_SIMILARITY_THRESHOLD = 0.85   # for re‑acquisition
    STRANGER_THRESHOLD = 0.30
