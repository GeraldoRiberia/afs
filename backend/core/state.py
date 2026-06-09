import threading
import queue as _queue
import numpy as np
from concurrent.futures import ThreadPoolExecutor
from core.config import MODEL_DIR
from services.single_tracker import SingleTracker
from services.multi_tracker import MultiTracker
from services.face_recognition import FaceRecognitionService
from services.audio_processing import AudioProcessor

class SystemState:
    def __init__(self):
        # Database Collections
        self.mongo_client = None
        self.users_collection = None
        self.audio_recordings_collection = None
        self.audio_settings_collection = None
        self.audio_angles_collection = None

        # OBS and Recording State
        self.latest_obs_frame = None
        self.obs_frame_lock = threading.Lock()
        self.is_obs_active = False
        self.is_recording = False
        self.video_writer = None
        self.recording_filename = ""

        # Syphon Virtual Camera State
        self.is_syphon_active = False
        self.syphon_server = None        # syphon.SyphonMetalServer instance
        self.syphon_texture = None       # pre-allocated MTLTexture
        self.syphon_lock = threading.Lock()
        self.syphon_queue = _queue.Queue(maxsize=1)   # drop-queue
        self.syphon_rgba_buf = None      # reusable RGBA buffer
        self.syphon_capture = None       # direct camera reader

        # EMA Smoothing
        self.current_cx = 0.5
        self.current_cy = 0.5
        self.current_scale = 1.0
        self.zoom_multiplier = 1.0

        # Real-time Target Tracking State
        self.current_target_angle = None
        self.current_target_distance = None

        # Trackers and Services (initialized as singletons)
        self.executor = ThreadPoolExecutor(max_workers=1)
        self.single_tracker = SingleTracker()
        self.multi_tracker = MultiTracker()
        self.face_service = FaceRecognitionService(str(MODEL_DIR))
        self.audio_processor = AudioProcessor(str(MODEL_DIR))

# Create the global singleton instance
state = SystemState()
