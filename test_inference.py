from services.single_tracker import SingleTracker
import cv2
import json

tracker = SingleTracker()
cap = cv2.VideoCapture("Model/my_scan.mp4")
frames = 0

print("Main User embeddings:", bool(tracker.main_user_embeddings))
print("Len:", len(tracker.main_user_embeddings))

while cap.isOpened() and frames < 10:
    ret, frame = cap.read()
    if not ret: break
    
    res = tracker.process_frame(frame)
    if res["boxes"]:
        print(f"Frame {frames} Boxes: {len(res['boxes'])}")
    else:
        print(f"Frame {frames}: No Output. Err: {res.get('error')}")
    frames += 1
