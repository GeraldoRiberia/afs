import cv2
import numpy as np
import logging
import threading
import queue as _queue
from core.config import _SYPHON_OUTPUT_W, _SYPHON_OUTPUT_H, _SYPHON_SMOOTH
from core.state import state
from services.cropping import _apply_crop_at_state

logger = logging.getLogger(__name__)

# Syphon (optional – macOS only)
try:
    import syphon
    from syphon.utils.numpy import copy_image_to_mtl_texture
    from syphon.utils.raw import create_mtl_texture
    _SYPHON_AVAILABLE = True
    logger.info("syphon-python loaded successfully.")
except ImportError:
    _SYPHON_AVAILABLE = False
    logger.warning(
        "syphon-python not found. Run: pip install syphon-python\n"
        "Syphon virtual camera will be unavailable."
    )

class SyphonDirectCapture:
    """Opens the system camera directly with cv2.VideoCapture and feeds
    the Syphon publisher at 30 fps, independent of the WebSocket pipeline.
    """

    def __init__(self, camera_idx: int = 0):
        self.camera_idx = camera_idx
        self._cap = None
        self._stop_evt = threading.Event()
        self._thread = None
        self._cx = 0.5
        self._cy = 0.5
        self._scale = 1.0

    def start(self) -> bool:
        self._stop_evt.clear()
        cap = cv2.VideoCapture(self.camera_idx)
        if not cap.isOpened():
            logger.error(f"SyphonDirectCapture: cannot open camera {self.camera_idx}")
            return False
        # Request 30 fps at 1280x720; the driver may round to the nearest mode
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, _SYPHON_OUTPUT_W)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, _SYPHON_OUTPUT_H)
        cap.set(cv2.CAP_PROP_FPS, 30)
        self._cap = cap
        self._thread = threading.Thread(
            target=self._loop, name="syphon-capture", daemon=True
        )
        self._thread.start()
        logger.info(
            f"SyphonDirectCapture started on camera {self.camera_idx} "
            f"({int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}×"
            f"{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))} "
            f"@ {int(cap.get(cv2.CAP_PROP_FPS))} fps)"
        )
        return True

    def stop(self):
        self._stop_evt.set()
        if self._cap is not None:
            self._cap.release()
            self._cap = None
        logger.info("SyphonDirectCapture stopped.")

    def _loop(self):
        cap = self._cap
        if cap is None:
            return
        while not self._stop_evt.is_set():
            ret, frame = cap.read()
            if not ret:
                self._stop_evt.wait(0.01)
                continue

            # Layer-2 EMA: smooth Syphon state toward YOLO target at 30fps
            self._cx    += (state.current_cx    - self._cx)    * _SYPHON_SMOOTH
            self._cy    += (state.current_cy    - self._cy)    * _SYPHON_SMOOTH
            self._scale += (state.current_scale - self._scale) * _SYPHON_SMOOTH

            # Crop using the Syphon-side state (smooth at 30fps)
            cropped = _apply_crop_at_state(frame, self._cx, self._cy, self._scale)
            # Enqueue to Syphon publisher
            _syphon_enqueue(cropped)

def _syphon_init(camera_idx: int = 0):
    """Create the Syphon Metal server, pre-allocate the texture, and start
    the direct-capture thread that feeds it at 30 fps."""
    if not _SYPHON_AVAILABLE:
        logger.warning("Cannot start Syphon: syphon-python not installed.")
        return False
    try:
        with state.syphon_lock:
            if state.syphon_server is None:
                state.syphon_server = syphon.SyphonMetalServer("AFS AutoFrame")
                state.syphon_texture = create_mtl_texture(
                    state.syphon_server.device, _SYPHON_OUTPUT_W, _SYPHON_OUTPUT_H
                )
                # Pre-allocate a reusable RGBA buffer to avoid per-frame malloc
                state.syphon_rgba_buf = np.zeros(
                    (_SYPHON_OUTPUT_H, _SYPHON_OUTPUT_W, 4), dtype=np.uint8
                )
                logger.info(
                    f"Syphon server 'AFS AutoFrame' started "
                    f"({_SYPHON_OUTPUT_W}×{_SYPHON_OUTPUT_H})."
                )
        # Start direct camera capture
        if state.syphon_capture is None or not state.syphon_capture._thread or \
                not state.syphon_capture._thread.is_alive():
            capture = SyphonDirectCapture(camera_idx=camera_idx)
            if not capture.start():
                return False
            state.syphon_capture = capture
        return True
    except Exception as e:
        logger.error(f"Syphon init failed: {e}")
        return False

def _syphon_stop():
    """Gracefully stop the Syphon server and direct-capture thread."""
    if state.syphon_capture is not None:
        state.syphon_capture.stop()
        state.syphon_capture = None
    with state.syphon_lock:
        state.is_syphon_active = False
        if state.syphon_server is not None:
            try:
                state.syphon_server.stop()
            except Exception:
                pass
            state.syphon_server = None
            state.syphon_texture = None
            state.syphon_rgba_buf = None
            logger.info("Syphon server stopped.")

def _syphon_enqueue(frame_bgr: np.ndarray):
    try:
        state.syphon_queue.put_nowait(frame_bgr)
    except _queue.Full:
        try:
            state.syphon_queue.get_nowait()          # drain the stale frame
        except _queue.Empty:
            pass
        try:
            state.syphon_queue.put_nowait(frame_bgr) # replace with newest
        except _queue.Full:
            pass

def _syphon_worker():
    """Dedicated daemon thread that owns all Metal/Syphon API calls."""
    if not _SYPHON_AVAILABLE:
        return
    logger.info("Syphon worker thread started.")
    while True:
        try:
            frame_bgr = state.syphon_queue.get(timeout=1.0)  # block until frame
        except _queue.Empty:
            continue

        with state.syphon_lock:
            srv = state.syphon_server
            tex = state.syphon_texture
            buf = state.syphon_rgba_buf

        if srv is None or tex is None or buf is None:
            continue

        try:
            h, w = frame_bgr.shape[:2]
            if w != _SYPHON_OUTPUT_W or h != _SYPHON_OUTPUT_H:
                frame_bgr = cv2.resize(
                    frame_bgr, (_SYPHON_OUTPUT_W, _SYPHON_OUTPUT_H),
                    interpolation=cv2.INTER_LINEAR
                )
            # Convert BGR → RGBA in-place into pre-allocated buffer
            cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGBA, dst=buf)
            copy_image_to_mtl_texture(buf, tex)
            srv.publish_frame_texture(tex)
        except Exception as e:
            logger.error(f"Syphon worker publish error: {e}")

# Start the Syphon worker daemon thread immediately
_syphon_thread = threading.Thread(
    target=_syphon_worker, name="syphon-publisher", daemon=True
)
_syphon_thread.start()
