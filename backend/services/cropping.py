import cv2
import numpy as np
import math
import logging
from core.config import SMOOTHING_FACTOR, TARGET_ASPECT_RATIO
from core.state import state

logger = logging.getLogger(__name__)

def decode_binary_image(img_data: bytes):
    """Decodes raw JPEG bytes into an OpenCV numpy array."""
    try:
        nparr = np.frombuffer(img_data, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        return img
    except Exception as e:
        logger.error(f"Failed to decode image: {e}")
        return None

def apply_center_stage_crop(frame, tracking_data):
    """
    Applies an exponential moving average (EMA) to smoothly pan and zoom
    the frame based on the tracking target bounding box.
    Returns the cropped frame.
    """
    h, w = frame.shape[:2]

    # Defaults
    target_cx = 0.5
    target_cy = 0.5
    target_scale = 1.0

    target_found = False

    # Calculate target state based on tracking data
    boxes = tracking_data.get("boxes", [])
    if tracking_data.get("mode") == "multi":
        if "aggregate_box" in tracking_data:
            ab = tracking_data["aggregate_box"]
            box_cx = (ab["x1"] + ab["x2"]) / 2.0
            box_cy = (ab["y1"] + ab["y2"]) / 2.0
            box_w = ab["x2"] - ab["x1"]
            box_h = ab["y2"] - ab["y1"]

            target_cx = box_cx / w
            target_cy = box_cy / h
            target_found = True

            # Target scale logic (from Dart): max dimension proportion * 1.5 margin
            max_dim = max(box_w / w, box_h / h)
            target_scale = 1.0 / (max_dim * 1.5)
            # Clamp scale
            target_scale = max(1.0, min(target_scale, 3.0))
    else:  # single
        target_box = None
        for b in boxes:
            if b.get("is_target"):
                target_box = b
                break

        if target_box:
            box_cx = (target_box["x1"] + target_box["x2"]) / 2.0
            box_cy = (target_box["y1"] + target_box["y2"]) / 2.0
            box_w = target_box["x2"] - target_box["x1"]
            box_h = target_box["y2"] - target_box["y1"]

            target_cx = box_cx / w
            target_cy = box_cy / h
            target_found = True

            max_dim = max(box_w / w, box_h / h)
            # slightly tighter for single person
            target_scale = 1.0 / (max_dim * 2.0)
            target_scale = max(1.0, min(target_scale, 3.0))

    if target_found:
        # Apply user zoom multiplier
        target_scale = max(1.0, min(target_scale * state.zoom_multiplier, 10.0))

        # Calculate distance and angle from the frame center (w/2, h/2) to the target bounding box center (box_cx, box_cy)
        center_x, center_y = w / 2.0, h / 2.0

        dx = box_cx - center_x
        dy = box_cy - center_y

        state.current_target_distance = math.hypot(dx, dy)
        # Convert atan2 result to 0-360 degrees
        angle = math.degrees(math.atan2(dy, dx))
        state.current_target_angle = angle % 360.0
    else:
        state.current_target_angle = None
        state.current_target_distance = None

    # Apply EMA smoothing
    state.current_cx += (target_cx - state.current_cx) * SMOOTHING_FACTOR
    state.current_cy += (target_cy - state.current_cy) * SMOOTHING_FACTOR
    state.current_scale += (target_scale - state.current_scale) * SMOOTHING_FACTOR

    # Calculate crop dimensions
    # When scale is S, the crop width is w / S
    crop_w = int(w / state.current_scale)
    crop_h = int(h / state.current_scale)

    # Enforce aspect ratio
    # If crop_w / crop_h is not 16:9, adjust one to match
    current_ar = crop_w / max(1, crop_h)
    if current_ar > TARGET_ASPECT_RATIO:
        # Too wide, shrink width
        crop_w = int(crop_h * TARGET_ASPECT_RATIO)
    else:
        # Too tall, shrink height
        crop_h = int(crop_w / TARGET_ASPECT_RATIO)

    # Calculate top-left point of crop, clamping to frame boundaries
    center_px_x = int(state.current_cx * w)
    center_px_y = int(state.current_cy * h)

    start_x = max(0, center_px_x - crop_w // 2)
    start_y = max(0, center_px_y - crop_h // 2)

    # Adjust if crop box goes out of bounds
    if start_x + crop_w > w:
        start_x = w - crop_w
    if start_y + crop_h > h:
        start_y = h - crop_h

    # Crop
    cropped = frame[start_y:start_y+crop_h, start_x:start_x+crop_w]
    return cropped

def _apply_crop_at_state(frame: np.ndarray, cx: float, cy: float, scale: float) -> np.ndarray:
    """Crop *frame* using the given (cx, cy, scale) values.
    Resolution-independent: cx/cy are 0-1 normalised, scale is the zoom factor."""
    h, w = frame.shape[:2]
    scale = max(scale, 1.0)
    crop_w = int(w / scale)
    crop_h = int(h / scale)

    # Enforce 16:9
    ar = crop_w / max(1, crop_h)
    if ar > TARGET_ASPECT_RATIO:
        crop_w = int(crop_h * TARGET_ASPECT_RATIO)
    else:
        crop_h = int(crop_w / TARGET_ASPECT_RATIO)

    # Clamp so we never go out-of-bounds
    crop_w = min(crop_w, w)
    crop_h = min(crop_h, h)

    center_px_x = int(cx * w)
    center_px_y = int(cy * h)

    start_x = max(0, center_px_x - crop_w // 2)
    start_y = max(0, center_px_y - crop_h // 2)
    if start_x + crop_w > w:
        start_x = w - crop_w
    if start_y + crop_h > h:
        start_y = h - crop_h

    return frame[start_y:start_y + crop_h, start_x:start_x + crop_w]

def _apply_current_crop(frame: np.ndarray) -> np.ndarray:
    """Convenience wrapper: crop using the live YOLO EMA globals.
    Used when no per-consumer smooth state is available."""
    return _apply_crop_at_state(frame, state.current_cx, state.current_cy, state.current_scale)
