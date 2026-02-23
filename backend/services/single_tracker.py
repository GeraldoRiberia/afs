import os
import cv2
import pickle
import numpy as np
import logging
from ultralytics import YOLO
from deepface import DeepFace

logger = logging.getLogger(__name__)

class SingleTracker:
    def __init__(self):
        logger.info("Initializing Single Tracker (Face Priority)")
        
        # Configuration matches face_model.py
        self.base_dir = "/Users/adisankarlalan/Documents/GitHub/afs-fl/Model"
        self.reference_video_path = os.path.join(self.base_dir, 'my_scan.mp4')
        self.model_name = "ArcFace"
        self.detector_model_path = os.path.join(self.base_dir, "yolov8n-face.pt")
        self.cache_file = os.path.join(self.base_dir, "embeddings_cache.pkl")
        
        # State
        self.priority_track_id = None
        self.known_tracks = {} # {track_id: is_main_user}
        self.track_retries = {} # {track_id: retry_count}
        
        self.max_retries = 20
        self.similarity_threshold = 0.70
        
        self.main_user_embeddings = []
        self._load_embeddings()
        
        try:
            self.model = YOLO(self.detector_model_path)
            logger.info("Loaded YOLO model")
        except Exception as e:
            logger.error(f"Failed to load YOLO model: {e}")
            self.model = None

    def _is_cache_valid(self, cache_data):
        if not cache_data:
            return False
        if cache_data.get('video_path') != 'my_scan.mp4' and cache_data.get('video_path') != self.reference_video_path:
            return False
        if cache_data.get('model_name') != self.model_name:
            return False
        if cache_data.get('version', 1) < 2:
            return False
        return True

    def _load_embeddings(self):
        logger.info("Loading main user embeddings...")
        cache_loaded = False
        
        if os.path.exists(self.cache_file):
            try:
                with open(self.cache_file, 'rb') as f:
                    cache_data = pickle.load(f)
                
                if self._is_cache_valid(cache_data):
                    self.main_user_embeddings = cache_data['embeddings']
                    logger.info("Loaded master signature from cache")
                    cache_loaded = True
            except Exception as e:
                logger.error(f"Could not load cache: {e}")
                
        if not cache_loaded:
            logger.warning(f"Cache invalid or not found at {self.cache_file}. Returning empty embeddings. Please run Model/face_model.py to generate cache.")
        
    def process_frame(self, frame):
        """
        Process a single BGR image frame for single face tracking.
        Returns a dictionary with tracking results.
        """
        results_data = {
            "boxes": [],
            "priority_id": self.priority_track_id,
            "error": None,
            "frame_width": int(frame.shape[1]),
            "frame_height": int(frame.shape[0])
        }
        
        if self.model is None:
            results_data["error"] = "Model not initialized"
            return results_data
            
        try:
            # RUN BYTETRACK
            results = self.model.track(frame, persist=True, tracker="bytetrack.yaml", verbose=False)
            
            if results and len(results) > 0 and results[0].boxes.id is not None:
                boxes = results[0].boxes.xyxy.cpu().numpy().astype(int)
                track_ids = results[0].boxes.id.cpu().numpy().astype(int)

                for box, track_id in zip(boxes, track_ids):
                    x1, y1, x2, y2 = box.tolist()
                    track_id = int(track_id)
                    max_similarity = 0.0
                    
                    # Lock resolution logic
                    if track_id not in self.known_tracks and len(self.main_user_embeddings) > 0:
                        if track_id not in self.track_retries:
                            self.track_retries[track_id] = 0

                        # Crop face
                        face_crop = frame[y1:y2, x1:x2]
                        
                        try:
                            # Strict check
                            current_face = DeepFace.represent(face_crop, model_name=self.model_name, enforce_detection=False)[0]["embedding"]
                            
                            for user_embedding in self.main_user_embeddings:
                                sim = np.dot(user_embedding, current_face) / (np.linalg.norm(user_embedding) * np.linalg.norm(current_face))
                                if sim > max_similarity:
                                    max_similarity = sim
                            
                            max_similarity = float(max_similarity)

                            if max_similarity > self.similarity_threshold: 
                                self.known_tracks[track_id] = True
                                self.priority_track_id = track_id
                                results_data["priority_id"] = track_id
                                if track_id in self.track_retries:
                                    del self.track_retries[track_id]
                            else:
                                self.track_retries[track_id] += 1
                                if self.track_retries[track_id] > self.max_retries:
                                    self.known_tracks[track_id] = False
                                    del self.track_retries[track_id]

                        except Exception as e:
                            # Exception means no face/blur => skip for this frame but count retry
                            logger.error(f"DeepFace failed on track_id {track_id}: {e}")
                            self.track_retries[track_id] += 1
                            if self.track_retries[track_id] > self.max_retries:
                                self.known_tracks[track_id] = False
                                del self.track_retries[track_id]
                    else:
                        # Ensures unknown tracks still get registered for scanning display
                        if track_id not in self.known_tracks and track_id not in self.track_retries:
                            self.track_retries[track_id] = 0

                    # Determine label and color representation
                    is_target = self.known_tracks.get(track_id, False)
                    if is_target:
                        label = f"TARGET LOCKED"
                        results_data["boxes"].append({
                            "id": track_id,
                            "x1": x1, "y1": y1,
                            "x2": x2, "y2": y2,
                            "is_target": True,
                            "label": label,
                            "similarity": max_similarity if 'max_similarity' in locals() else -1.0
                        })
                    elif track_id in self.track_retries:
                        # Draw scanning box
                        label = f"SCANNING"
                        results_data["boxes"].append({
                            "id": track_id,
                            "x1": x1, "y1": y1,
                            "x2": x2, "y2": y2,
                            "is_target": False,
                            "label": label,
                            "similarity": max_similarity if 'max_similarity' in locals() else -1.0
                        })
                    
        except Exception as e:
            logger.error(f"Error during SingleTrack: {e}")
            results_data["error"] = str(e)

        return results_data
