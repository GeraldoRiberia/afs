import cv2
from ultralytics import YOLO
from deepface import DeepFace
import numpy as np
import pickle
import os

# --- CONFIGURATION ---
MAIN_USER_IMAGES = ["Adi.jpg"]  # List of reference images
REFERENCE_VIDEO_PATH = 'my_scan.mp4'     # Set to "my_scan.mp4" to use a video for reference (extracts multiple angles)
MODEL_NAME = "ArcFace"           # Accurate and fast for embeddings
DETECTOR_MODEL = "yolov8n-face.pt" # Lightweight face detector for YOLO
CACHE_FILE = "embeddings_cache.pkl"  # Cache file for storing embeddings

# 1. PRE-COMPUTE MAIN USER EMBEDDINGS (The "One-Time Scan")
print("Loading Main User signatures...")
main_user_embeddings = []

# Helper function to check if cache is valid
def is_cache_valid(cache_data):
    """Check if the cached embeddings are still valid"""
    if not cache_data:
        return False
    
    # Check if video path matches
    if cache_data.get('video_path') != REFERENCE_VIDEO_PATH:
        return False
    
    # Check if model name matches
    if cache_data.get('model_name') != MODEL_NAME:
        return False
    
    # Check cache version (version 2 has quality filtering)
    if cache_data.get('version', 1) < 2:
        print(" ✗ Old cache version detected (no quality filtering), re-extracting...")
        return False
    
    # Check if video file still exists and hasn't been modified
    if REFERENCE_VIDEO_PATH and os.path.exists(REFERENCE_VIDEO_PATH):
        current_mtime = os.path.getmtime(REFERENCE_VIDEO_PATH)
        if cache_data.get('video_mtime') != current_mtime:
            return False
    
    return True

# Try to load from cache
cache_loaded = False
if os.path.exists(CACHE_FILE):
    try:
        with open(CACHE_FILE, 'rb') as f:
            cache_data = pickle.load(f)
        
        if is_cache_valid(cache_data):
            main_user_embeddings = cache_data['embeddings']
            num_frames = cache_data.get('num_frames_used', 'unknown')
            print(f" ✓ Loaded master signature from cache (created from {num_frames} high-quality frames)")
            cache_loaded = True
        else:
            if cache_data.get('version', 1) >= 2:
                print(" ✗ Cache invalid (video or model changed), re-extracting...")
    except Exception as e:
        print(f" ✗ Could not load cache: {e}")

# If cache not loaded, extract embeddings
if not cache_loaded:
    print("Extracting Main User signatures with quality filtering...")
    
    # Quality filtering configuration
    NUM_BEST_FRAMES = 10
    MIN_BLUR_THRESHOLD = 10  # Lowered threshold - adjust if needed (typical range: 50-200)
    BLUR_WEIGHT = 0.6
    FRONTAL_WEIGHT = 0.4
    
    # Helper function to calculate blur score (Laplacian variance)
    def calculate_blur_score(image):
        """Calculate sharpness using Laplacian variance. Higher = sharper."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        return laplacian_var
    
    # Helper function to calculate frontal face score
    def calculate_frontal_score(face_data):
        """Calculate how frontal the face is based on facial landmarks symmetry."""
        try:
            # DeepFace returns facial area with landmarks
            facial_area = face_data.get('facial_area', {})
            
            # Simple heuristic: larger face area = more frontal (closer to camera)
            # In a more advanced version, we'd use actual landmark positions
            area = facial_area.get('w', 0) * facial_area.get('h', 0)
            
            # Normalize score (assuming max face area is ~50000 pixels)
            frontal_score = min(area / 50000.0, 1.0) * 100
            return frontal_score
        except:
            return 50.0  # Default middle score
    
    # A. Load from static images (commented out for now)
    # for img_path in MAIN_USER_IMAGES:
    #     try:
    #         embedding = DeepFace.represent(img_path=img_path, model_name=MODEL_NAME)[0]["embedding"]
    #         main_user_embeddings.append(embedding)
    #         print(f" - Loaded signature from image: {img_path}")
    #     except Exception as e:
    #         print(f" - Could not load image {img_path}: {e}")
    
    # B. Load from Reference Video with Quality Filtering
    if REFERENCE_VIDEO_PATH:
        print(f"Processing reference video scan: {REFERENCE_VIDEO_PATH}...")
        print("Phase 1: Analyzing frame quality...")
        
        cap_ref = cv2.VideoCapture(REFERENCE_VIDEO_PATH)
        total_frames = int(cap_ref.get(cv2.CAP_PROP_FRAME_COUNT))
        
        # Store candidate frames with quality metrics
        candidate_frames = []
        
        frame_idx = 0
        while cap_ref.isOpened():
            ret, frame = cap_ref.read()
            if not ret: break
            
            # Sample every 15th frame (approx 2 per second at 30fps)
            if frame_idx % 15 == 0:
                # Calculate blur score
                blur_score = calculate_blur_score(frame)
                
                # Debug: Show all blur scores
                if blur_score <= MIN_BLUR_THRESHOLD:
                    print(f" ✗ Frame {frame_idx}: Blur={blur_score:.1f} (too blurry, skipped)")
                
                # Skip very blurry frames
                if blur_score > MIN_BLUR_THRESHOLD:
                    try:
                        # Use DeepFace to detect and get facial data
                        face_data = DeepFace.represent(frame, model_name=MODEL_NAME, enforce_detection=True)[0]
                        
                        # Calculate frontal score
                        frontal_score = calculate_frontal_score(face_data)
                        
                        # Combined quality score
                        quality_score = (blur_score * BLUR_WEIGHT) + (frontal_score * FRONTAL_WEIGHT)
                        
                        # Store frame info
                        candidate_frames.append({
                            'frame_idx': frame_idx,
                            'frame': frame.copy(),
                            'blur_score': blur_score,
                            'frontal_score': frontal_score,
                            'quality_score': quality_score,
                            'embedding': face_data['embedding']
                        })
                        
                        print(f" ✓ Frame {frame_idx}: Quality={quality_score:.1f} (Blur={blur_score:.1f}, Frontal={frontal_score:.1f})")
                    except Exception as e:
                        print(f" ✗ Frame {frame_idx}: Blur={blur_score:.1f} (no face detected)")
                        pass  # Skip frames where face isn't clearly detected
            
            frame_idx += 1
        
        cap_ref.release()
        
        if not candidate_frames:
            print("Error: No valid frames found in video.")
        else:
            print(f"\nPhase 2: Selecting top {NUM_BEST_FRAMES} frames with temporal spacing...")
            
            # Sort by quality score
            candidate_frames.sort(key=lambda x: x['quality_score'], reverse=True)
            
            # Implement temporal spacing: divide video into segments
            segment_size = total_frames // NUM_BEST_FRAMES
            selected_frames = []
            
            # For each segment, find the best frame
            for segment_idx in range(NUM_BEST_FRAMES):
                segment_start = segment_idx * segment_size
                segment_end = (segment_idx + 1) * segment_size
                
                # Find best frame in this segment
                best_in_segment = None
                best_quality = -1
                
                for candidate in candidate_frames:
                    if segment_start <= candidate['frame_idx'] < segment_end:
                        if candidate['quality_score'] > best_quality:
                            best_quality = candidate['quality_score']
                            best_in_segment = candidate
                
                # If we found a good frame in this segment, use it
                if best_in_segment:
                    selected_frames.append(best_in_segment)
                    print(f" ✓ Segment {segment_idx+1}: Frame {best_in_segment['frame_idx']} (Quality={best_in_segment['quality_score']:.1f})")
            
            # If we didn't get enough frames with temporal spacing, fill with top quality frames
            if len(selected_frames) < NUM_BEST_FRAMES:
                print(f"\nFilling remaining slots with highest quality frames...")
                for candidate in candidate_frames:
                    if candidate not in selected_frames:
                        selected_frames.append(candidate)
                        print(f" ✓ Added Frame {candidate['frame_idx']} (Quality={candidate['quality_score']:.1f})")
                        if len(selected_frames) >= NUM_BEST_FRAMES:
                            break
            
            # Extract embeddings from selected frames
            print(f"\nPhase 3: Averaging {len(selected_frames)} embeddings...")
            embeddings_to_average = [frame['embedding'] for frame in selected_frames]
            
            # Calculate mean embedding (master signature)
            master_embedding = np.mean(embeddings_to_average, axis=0).tolist()
            main_user_embeddings = [master_embedding]
            
            print(f" ✓ Created master signature from {len(selected_frames)} high-quality frames")
    
    # Save to cache
    if main_user_embeddings and REFERENCE_VIDEO_PATH:
        try:
            cache_data = {
                'video_path': REFERENCE_VIDEO_PATH,
                'video_mtime': os.path.getmtime(REFERENCE_VIDEO_PATH),
                'model_name': MODEL_NAME,
                'embeddings': main_user_embeddings,
                'version': 2,  # Version 2 with quality filtering
                'num_frames_used': len(selected_frames) if 'selected_frames' in locals() else 0
            }
            with open(CACHE_FILE, 'wb') as f:
                pickle.dump(cache_data, f)
            print(f" ✓ Saved master signature to cache")
        except Exception as e:
            print(f" ✗ Could not save cache: {e}")

if not main_user_embeddings:
    print("Error: No valid reference images or video frames found. Exiting.")
    exit()

# 2. INITIALIZE TRACKER AND CAMERA
model = YOLO(DETECTOR_MODEL)
cap = cv2.VideoCapture(1)

# Tracking state
priority_track_id = None
known_tracks = {} # Store {track_id: is_main_user}
track_retries = {} # Store {track_id: retry_count}

MAX_RETRIES = 20 # Number of frames to try identifying a face before giving up
SIMILARITY_THRESHOLD = 0.70 # Stricter threshold to avoid false positives

while cap.isOpened():
    success, frame = cap.read()
    if not success: break

    # 3. RUN BYTETRACK (Detection + Tracking)
    results = model.track(frame, persist=True, tracker="bytetrack.yaml", verbose=False)
    
    if results[0].boxes.id is not None:
        boxes = results[0].boxes.xyxy.cpu().numpy().astype(int)
        track_ids = results[0].boxes.id.cpu().numpy().astype(int)

        for box, track_id in zip(boxes, track_ids):
            # 4. IDENTIFICATION LOGIC
            max_similarity = 0 # Default if we don't check
            
            # Only process if we haven't made a final decision yet
            if track_id not in known_tracks:
                # Initialize retry counter if new
                if track_id not in track_retries:
                    track_retries[track_id] = 0

                # Crop face
                x1, y1, x2, y2 = box
                face_crop = frame[y1:y2, x1:x2]
                
                try:
                    # STRICT CHECK: enforce_detection=True ensures we only look at GOOD frames
                    # If this fails (no face/blur/angle), we skip everything below and don't count it as a retry
                    current_face = DeepFace.represent(face_crop, model_name=MODEL_NAME, enforce_detection=True)[0]["embedding"]
                    
                    # Manual Cosine Similarity check against ALL reference images
                    for user_embedding in main_user_embeddings:
                        sim = np.dot(user_embedding, current_face) / (np.linalg.norm(user_embedding) * np.linalg.norm(current_face))
                        if sim > max_similarity:
                            max_similarity = sim
                    
                    if max_similarity > SIMILARITY_THRESHOLD: 
                        known_tracks[track_id] = True
                        priority_track_id = track_id
                        print(f"Target Found! Locked to ID: {track_id} (Sim: {max_similarity:.2f})")
                        # Clean up retry counter
                        if track_id in track_retries:
                            del track_retries[track_id]
                    else:
                        # Match failed on this specific frame
                        track_retries[track_id] += 1
                        
                        # If we've tried enough times and still no match, mark as Stranger
                        if track_retries[track_id] > MAX_RETRIES:
                            known_tracks[track_id] = False
                            print(f"ID {track_id} marked as Unknown (Max Sim: {max_similarity:.2f})")
                            del track_retries[track_id]

                except:
                    # DeepFace couldn't detect a face in this crop (blur, back of head, etc.)
                    # Do NOT increment retry counter. Wait for a better frame.
                    continue

            # 5. VISUALIZATION & PRIORITY
            is_target = known_tracks.get(track_id, False) # precise lookup
            color = (0, 0, 255) if is_target else (0, 255, 0)
            
            # Label logic
            if is_target:
                label = f"TARGET LOCKED ({max_similarity:.2f})" if max_similarity > 0 else "TARGET LOCKED"
            elif track_id in track_retries:
                label = f"ID: {track_id} (Scan: {max_similarity:.2f})"
            else:
                label = f"ID: {track_id} (Stranger)"
            
            cv2.rectangle(frame, (box[0], box[1]), (box[2], box[3]), color, 2)
            cv2.putText(frame, label, (box[0], box[1] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

    cv2.imshow("ByteTrack + DeepFace Priority", frame)
    if cv2.waitKey(1) & 0xFF == ord('q'): break

cap.release()
cv2.destroyAllWindows()