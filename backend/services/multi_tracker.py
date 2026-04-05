import os
import cv2
import numpy as np
import logging
from ultralytics import YOLO
from pathlib import Path

logger = logging.getLogger(__name__)

class MultiTracker:
    def __init__(self):
        logger.info("Initializing Multi Tracker (Group Centroid)")
        
        # Determine paths

        # Get the directory containing the current script (multi_tracker.py)
        base_dir = Path(__file__).parent.parent

        # Model folder is now inside backend/
        detector_model_path = base_dir / "Model" / "yolov8n-face.pt"
        print(detector_model_path,"de")
        
        try:
            self.model = YOLO(detector_model_path)
            logger.info(f"Loaded YOLO model from {detector_model_path}")
        except Exception as e:
            logger.error(f"Failed to load YOLO model: {e}")
            self.model = None

    def process_frame(self, frame):
        """
        Process a single BGR image frame for group object tracking.
        Returns a dictionary with tracking results (individual boxes + aggregate box).
        """
        results_data = {
            "individual_boxes": [],
            "aggregate_box": None,
            "centroid": None,
            "error": None,
            "frame_width": int(frame.shape[1]),
            "frame_height": int(frame.shape[0])
        }

        if self.model is None:
            results_data["error"] = "Model not initialized"
            return results_data
            
        try:
            # RUN BYTETRACK (Detection + Tracking)
            results = self.model.track(frame, persist=True, tracker="bytetrack.yaml", verbose=False)
            
            if results and len(results) > 0 and results[0].boxes.id is not None:
                boxes = results[0].boxes.xyxy.cpu().numpy().astype(int)
                track_ids = results[0].boxes.id.cpu().numpy().astype(int)

                all_x1, all_y1, all_x2, all_y2 = [], [], [], []

                for box, track_id in zip(boxes, track_ids):
                    x1, y1, x2, y2 = box.tolist()
                    
                    all_x1.append(x1)
                    all_y1.append(y1)
                    all_x2.append(x2)
                    all_y2.append(y2)

                    results_data["individual_boxes"].append({
                        "id": int(track_id),
                        "x1": int(x1), "y1": int(y1), 
                        "x2": int(x2), "y2": int(y2)
                    })

                # Calculate Aggregate Bounding Box if faces exist
                if len(all_x1) > 0:
                    agg_x1 = int(min(all_x1))
                    agg_y1 = int(min(all_y1))
                    agg_x2 = int(max(all_x2))
                    agg_y2 = int(max(all_y2))

                    # Aggregate Centroid
                    agg_cx = (agg_x1 + agg_x2) // 2
                    agg_cy = (agg_y1 + agg_y2) // 2

                    results_data["aggregate_box"] = {
                        "x1": agg_x1, "y1": agg_y1,
                        "x2": agg_x2, "y2": agg_y2
                    }
                    results_data["centroid"] = {
                        "cx": agg_cx,
                        "cy": agg_cy
                    }

        except Exception as e:
            logger.error(f"Error during ByteTrack: {e}")
            results_data["error"] = str(e)
            
        return results_data
