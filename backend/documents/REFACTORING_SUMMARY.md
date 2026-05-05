# Refactoring Summary

## What Was Done

### 1. **Model Directory Usage Analysis**
The backend uses the following files from `/Model/` directory:
- `embeddings_cache.pkl` - Face recognition embeddings cache
- `yolov8n-face.pt` - YOLO face detection model
- `my_scan.mp4` - Reference 360-degree scan video
- `Adi.jpg` - Reference images

Both `single_tracker.py` and `multi_tracker.py` access the Model directory.

### 2. **Created New Services**

#### `services/face_recognition.py`
- Extracted face recognition logic from `Model/face_model.py`
- Class: `FaceRecognitionService`
- Methods:
  - `extract_embeddings_from_video()` - Process 360° video with quality filtering
  - `extract_embeddings_from_image()` - Process single reference image
  - `save_embeddings_cache()` - Save processed embeddings
  - `load_embeddings_cache()` - Load cached embeddings
  - `calculate_blur_score()` - Image sharpness detection
  - `calculate_frontal_score()` - Face frontality score

#### `services/audio_processing.py`
- New service for audio streaming with angle data
- Class: `AudioProcessor`
- Methods:
  - `create_audio_stream()` - Start new recording session
  - `write_audio_chunk()` - Write audio with optional angle metadata
  - `close_audio_stream()` - Finalize recording
  - `get_audio_files()` - List all recordings

### 3. **Added API Endpoints to `server.py`**

#### Face Recognition APIs:
- `POST /api/face/upload-video` - Upload 360° reference video
- `POST /api/face/upload-image` - Upload reference image
- `GET /api/face/cache-status` - Check embeddings cache status

#### Audio Streaming APIs:
- `POST /api/audio/start-stream` - Start audio recording session
- `WebSocket /ws/audio/{session_id}` - Stream audio with angle data
- `POST /api/audio/stop-stream/{session_id}` - Stop recording
- `GET /api/audio/recordings` - List all recordings

### 4. **File Storage Structure**
```
/Model/
├── my_scan.mp4                    # Reference video (uploaded via API)
├── ref_*.jpg                      # Reference images (uploaded via API)
├── embeddings_cache.pkl           # Processed face embeddings
├── yolov8n-face.pt               # YOLO model (static)
└── audio_recordings/
    ├── audio_{uuid}_{timestamp}.wav           # Audio recording
    └── audio_{uuid}_{timestamp}_metadata.txt  # Angle metadata (CSV)
```

### 5. **Audio Metadata Format**
The metadata file stores timestamp and angle in CSV format:
```csv
timestamp,angle
0.000,45.50
0.064,46.20
0.128,47.00
```

## How to Use

### Upload 360-Degree Video:
```bash
curl -X POST "http://localhost:8000/api/face/upload-video" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@my_360_scan.mp4"
```

### Upload Reference Image:
```bash
curl -X POST "http://localhost:8000/api/face/upload-image" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@reference.jpg"
```

### Start Audio Stream:
```bash
# 1. Start stream (get session_id)
curl -X POST "http://localhost:8000/api/audio/start-stream" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "sample_rate=16000" \
  -F "channels=1"

# 2. Connect via WebSocket and stream
# ws://localhost:8000/ws/audio/{session_id}

# 3. Send audio chunks (binary or JSON with angle)
# Binary: raw 16-bit PCM audio bytes
# JSON: {"audio_data": "base64...", "angle": 45.5}

# 4. Stop: {"command": "stop"}
```

## Key Features

1. **Quality Filtering**: Video processing uses blur detection and frontal face scoring to select best frames
2. **Temporal Spacing**: Selects frames evenly distributed across the video for comprehensive coverage
3. **Angle Tracking**: Audio streams can include direction/angle metadata for spatial audio analysis
4. **Mono/Stereo Support**: Configurable audio channels (1 or 2)
5. **Authentication**: All endpoints protected with JWT tokens
6. **Async Processing**: CPU-intensive tasks run in thread pool executor

## Original face_model.py

The original file at `/Model/face_model.py` remains unchanged and can still be run standalone for testing or manual processing. The new API provides the same functionality but in a service-oriented architecture accessible via HTTP/WebSocket.

## Dependencies

All required packages are already in `requirements.txt`:
- FastAPI, Uvicorn
- OpenCV (cv2)
- DeepFace
- Ultralytics (YOLO)
- NumPy
- Wave (stdlib)

No additional dependencies needed!
