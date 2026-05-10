import os
from pathlib import Path
import cv2
import pickle
import numpy as np
import logging
from ultralytics import YOLO
from deepface import DeepFace
from pathlib import Path

logger = logging.getLogger(__name__)

class SingleTracker:
    def __init__(self):
        logger.info("Initializing Single Tracker (Face Priority)")
        
        # Configuration matches face_model.py
        # self.base_dir = "/Users/adisankarlalan/Documents/GitHub/afs-fl/Model"
        base_dir = Path(__file__).parent
        self.base_dir = base_dir.parent / "Model" 
        print(self.base_dir,"base")

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
        # User-specific embeddings are supplied by the websocket auth flow.
        # Do not use the local generic cache for strict single-user tracking.
        
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
        
    def process_frame(self, frame, custom_embeddings=None):
        """
        Process a single BGR image frame for single face tracking.
        Returns a dictionary with tracking results.
        """
        results_data = {
            "boxes": [],
            "priority_id": self.priority_track_id,
            "error": None,
            "frame_width": int(frame.shape[1]),
            "frame_height": int(frame.shape[0]),
            "single_status": "NO EMBEDDINGS",
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
                
                keypoints = None
                if hasattr(results[0], 'keypoints') and results[0].keypoints is not None:
                    keypoints = results[0].keypoints.xy.cpu().numpy()

                for idx, (box, track_id) in enumerate(zip(boxes, track_ids)):
                    x1, y1, x2, y2 = box.tolist()
                    track_id = int(track_id)
                    max_similarity = 0.0
                    
                    # Compute Head Pose
                    yaw = 0.0
                    pitch = 0.0
                    if keypoints is not None and len(keypoints) > idx:
                        kpts = keypoints[idx]
                        if len(kpts) >= 5:
                            lex, ley = kpts[0]
                            rex, rey = kpts[1]
                            nx, ny = kpts[2]
                            lmx, lmy = kpts[3]
                            rmx, rmy = kpts[4]
                            
                            # Yaw: (-) turned left, (+) turned right
                            l_nose = abs(nx - lex)
                            r_nose = abs(nx - rex)
                            yaw = (l_nose - r_nose) / (l_nose + r_nose + 1e-6)
                            
                            # Pitch: (-) looking up, (+) looking down
                            eye_cy = (ley + rey) / 2
                            mouth_cy = (lmy + rmy) / 2
                            n_eye = ny - eye_cy
                            n_mouth = mouth_cy - ny
                            pitch = (n_eye - n_mouth) / (n_eye + n_mouth + 1e-6)
                            
                    # Lock resolution logic
                    embeddings_to_check = custom_embeddings if custom_embeddings is not None and len(custom_embeddings) > 0 else []
                    
                    if track_id not in self.known_tracks and len(embeddings_to_check) > 0:
                        if track_id not in self.track_retries:
                            self.track_retries[track_id] = 0

                        # Crop face
                        face_crop = frame[y1:y2, x1:x2]
                        
                        try:
                            # Strict check against the current user's embeddings only
                            current_face = DeepFace.represent(face_crop, model_name=self.model_name, enforce_detection=False)[0]["embedding"]
                            
                            for user_embedding in embeddings_to_check:
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
                            "similarity": max_similarity if 'max_similarity' in locals() else -1.0,
                            "yaw": float(yaw),
                            "pitch": float(pitch)
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
                            "similarity": max_similarity if 'max_similarity' in locals() else -1.0,
                            "yaw": float(yaw),
                            "pitch": float(pitch)
                        })
                    
        except Exception as e:
            logger.error(f"Error during SingleTrack: {e}")
            results_data["error"] = str(e)

        # Publish strict single-mode state for the frontend HUD.
        embeddings_available = custom_embeddings is not None and len(custom_embeddings) > 0
        if embeddings_available:
            if any(box.get("is_target", False) for box in results_data["boxes"]):
                results_data["single_status"] = "LOCKED"
            elif len(results_data["boxes"]) > 0:
                results_data["single_status"] = "SEARCHING"
            else:
                results_data["single_status"] = "NO FACE"
        else:
            results_data["single_status"] = "NO EMBEDDINGS"

        return results_data
