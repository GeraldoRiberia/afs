import pyvirtualcam
import numpy as np

try:
    with pyvirtualcam.Camera(width=1280, height=720, fps=30) as cam:
        print(f"Virtual camera started: {cam.device} ({cam.width}x{cam.height} @ {cam.fps}fps)")
        cam.send(np.zeros((720, 1280, 4), np.uint8))
except Exception as e:
    print(f"FAILED VCAM: {e}")
