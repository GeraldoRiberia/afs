import cv2
from ultralytics import YOLO
import numpy as np

import os

# --- CONFIGURATION ---
# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))
DETECTOR_MODEL = os.path.join(script_dir, "yolov8n-face.pt") # Lightweight face detector for YOLO

# 1. INITIALIZE TRACKER AND CAMERA
model = YOLO(DETECTOR_MODEL)
# Using camera index 2 as per previous configuration. Change to 0 if needed.
cap = cv2.VideoCapture(2) 

print("Starting Face Tracking (No Recognition)...")
print("Press 'q' to quit.")

while cap.isOpened():
    success, frame = cap.read()
    if not success: 
        print("Failed to read frame from camera.")
        break

    # 2. RUN BYTETRACK (Detection + Tracking)
    results = model.track(frame, persist=True, tracker="bytetrack.yaml", verbose=False)
    
    if results[0].boxes.id is not None:
        boxes = results[0].boxes.xyxy.cpu().numpy().astype(int)
        track_ids = results[0].boxes.id.cpu().numpy().astype(int)

        # Collect all boxes to calculate aggregate
        all_x1 = []
        all_y1 = []
        all_x2 = []
        all_y2 = []

        for box, track_id in zip(boxes, track_ids):
            x1, y1, x2, y2 = box
            
            # Add to lists for aggregate calculation
            all_x1.append(x1)
            all_y1.append(y1)
            all_x2.append(x2)
            all_y2.append(y2)

            # Visuals - Individual Bounding Box (Green)
            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(frame, f"ID: {track_id}", (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)

        # Calculate Aggregate Bounding Box if faces exist
        if len(all_x1) > 0:
            agg_x1 = min(all_x1)
            agg_y1 = min(all_y1)
            agg_x2 = max(all_x2)
            agg_y2 = max(all_y2)

            # Aggregate Centroid
            agg_cx = (agg_x1 + agg_x2) // 2
            agg_cy = (agg_y1 + agg_y2) // 2

            # Visuals - Aggregate Bounding Box (Blue)
            # Add some padding
            padding = 10
            agg_x1 = max(0, agg_x1 - padding)
            agg_y1 = max(0, agg_y1 - padding)
            agg_x2 = min(frame.shape[1], agg_x2 + padding)
            agg_y2 = min(frame.shape[0], agg_y2 + padding)

            cv2.rectangle(frame, (agg_x1, agg_y1), (agg_x2, agg_y2), (255, 0, 0), 3)
            
            # Aggregate Centroid - Large Blue Dot
            cv2.circle(frame, (agg_cx, agg_cy), 8, (255, 0, 0), -1)
            
            # Label
            label = f"GROUP CENTER ({agg_cx}, {agg_cy})"
            cv2.putText(frame, label, (agg_x1, agg_y1 - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 0), 2)

    cv2.imshow("Face Tracking - Centroids", frame)
    if cv2.waitKey(1) & 0xFF == ord('q'): break

cap.release()
cv2.destroyAllWindows()