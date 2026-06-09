import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# JWT Configuration
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

# Model Directory
# Resolves /backend/core/config.py -> parent parent -> /backend/Model
MODEL_DIR = Path(__file__).resolve().parent.parent / "Model"

# Image and Tracking parameters
SMOOTHING_FACTOR = 0.90
TARGET_ASPECT_RATIO = 16.0 / 9.0

# Syphon camera parameters
_SYPHON_OUTPUT_W = 1280
_SYPHON_OUTPUT_H = 720
_SYPHON_SMOOTH = 0.08
