import cv2
from ultralytics import YOLO
from deepface import DeepFace
import numpy as np
import pickle
import os
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

class FaceRecognitionService:
    def __init__(self, model_dir: str):
        self.model_dir = Path(model_dir)
        self.model_name = "ArcFace"
        self.detector_model = "yolov8n-face.pt"
        self.cache_file = self.model_dir / "embeddings_cache.pkl"
        
        self.num_best_frames = 10
        self.min_blur_threshold = 10
        self.blur_weight = 0.6
        self.frontal_weight = 0.4
    
    def calculate_blur_score(self, image):
        """Calculate sharpness using Laplacian variance."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        return laplacian_var
    
    def calculate_frontal_score(self, face_data):
        """Calculate how frontal the face is based on facial area."""
        try:
            facial_area = face_data.get('facial_area', {})
            area = facial_area.get('w', 0) * facial_area.get('h', 0)
            frontal_score = min(area / 50000.0, 1.0) * 100
            return frontal_score
        except:
            return 50.0
    
    def extract_embeddings_from_video(self, video_path: str):
        """Extract high-quality face embeddings from a 360-degree scan video."""
        logger.info(f"Processing reference video scan: {video_path}")
        logger.info("Phase 1: Analyzing frame quality...")
        
        cap_ref = cv2.VideoCapture(video_path)
        total_frames = int(cap_ref.get(cv2.CAP_PROP_FRAME_COUNT))
        
        candidate_frames = []
        frame_idx = 0
        
        while cap_ref.isOpened():
            ret, frame = cap_ref.read()
            if not ret:
                break
            
            if frame_idx % 15 == 0:
                blur_score = self.calculate_blur_score(frame)
                
                if blur_score <= self.min_blur_threshold:
                    logger.debug(f"Frame {frame_idx}: Blur={blur_score:.1f} (too blurry, skipped)")
                
                if blur_score > self.min_blur_threshold:
                    try:
                        face_data = DeepFace.represent(frame, model_name=self.model_name, enforce_detection=True)[0]
                        frontal_score = self.calculate_frontal_score(face_data)
                        quality_score = (blur_score * self.blur_weight) + (frontal_score * self.frontal_weight)
                        
                        candidate_frames.append({
                            'frame_idx': frame_idx,
                            'frame': frame.copy(),
                            'blur_score': blur_score,
                            'frontal_score': frontal_score,
                            'quality_score': quality_score,
                            'embedding': face_data['embedding']
                        })
                        
                        logger.debug(f"Frame {frame_idx}: Quality={quality_score:.1f}")
                    except Exception as e:
                        logger.debug(f"Frame {frame_idx}: No face detected - {e}")
            
            frame_idx += 1
        
        cap_ref.release()
        
        if not candidate_frames:
            raise ValueError("No valid frames found in video")
        
        logger.info(f"Phase 2: Selecting top {self.num_best_frames} frames with temporal spacing...")
        candidate_frames.sort(key=lambda x: x['quality_score'], reverse=True)
        
        segment_size = total_frames // self.num_best_frames
        selected_frames = []
        
        for segment_idx in range(self.num_best_frames):
            segment_start = segment_idx * segment_size
            segment_end = (segment_idx + 1) * segment_size
            
            best_in_segment = None
            best_quality = -1
            
            for candidate in candidate_frames:
                if segment_start <= candidate['frame_idx'] < segment_end:
                    if candidate['quality_score'] > best_quality:
                        best_quality = candidate['quality_score']
                        best_in_segment = candidate
            
            if best_in_segment:
                selected_frames.append(best_in_segment)
                logger.debug(f"Segment {segment_idx+1}: Frame {best_in_segment['frame_idx']}")
        
        if len(selected_frames) < self.num_best_frames:
            for candidate in candidate_frames:
                if candidate not in selected_frames:
                    selected_frames.append(candidate)
                    if len(selected_frames) >= self.num_best_frames:
                        break
        
        logger.info(f"Phase 3: Averaging {len(selected_frames)} embeddings...")
        embeddings_to_average = [frame['embedding'] for frame in selected_frames]
        master_embedding = np.mean(embeddings_to_average, axis=0).tolist()
        
        return [master_embedding], len(selected_frames)
    
    def extract_embeddings_from_image(self, image_path: str):
        """Extract face embedding from a single image."""
        try:
            embedding = DeepFace.represent(img_path=image_path, model_name=self.model_name)[0]["embedding"]
            return [embedding]
        except Exception as e:
            logger.error(f"Could not extract embedding from {image_path}: {e}")
            raise
    
    def save_embeddings_cache(self, embeddings, video_path: str, num_frames_used: int):
        """Save embeddings to cache file."""
        cache_data = {
            'video_path': video_path,
            'video_mtime': os.path.getmtime(video_path) if os.path.exists(video_path) else None,
            'model_name': self.model_name,
            'embeddings': embeddings,
            'version': 2,
            'num_frames_used': num_frames_used
        }
        
        with open(self.cache_file, 'wb') as f:
            pickle.dump(cache_data, f)
        
        logger.info(f"Saved embeddings cache to {self.cache_file}")
    
    def load_embeddings_cache(self):
        """Load embeddings from cache file."""
        if not os.path.exists(self.cache_file):
            return None
        
        try:
            with open(self.cache_file, 'rb') as f:
                cache_data = pickle.load(f)
            return cache_data
        except Exception as e:
            logger.error(f"Could not load cache: {e}")
            return None
