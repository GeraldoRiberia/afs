import cv2
import numpy as np
try:
    fourcc = cv2.VideoWriter_fourcc(*'avc1')
    out = cv2.VideoWriter('test_avc1.mp4', fourcc, 5.0, (640, 480))
    for i in range(10):
        frame = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
        out.write(frame)
    out.release()
    print("avc1 SUCCESS")
except Exception as e:
    print(f"FAILED: {e}")
