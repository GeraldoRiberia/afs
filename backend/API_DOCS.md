# API Documentation

## Overview
This document describes the new API endpoints added to the AFS backend for face recognition and audio streaming.

## Face Recognition APIs

### 1. Upload 360-Degree Reference Video
**Endpoint:** `POST /api/face/upload-video`

**Description:** Upload a 360-degree reference video for face recognition training. The video will be processed to extract high-quality face embeddings.

**Authentication:** Required (JWT token)

**Request:**
- Content-Type: `multipart/form-data`
- Body: `file` (video file - .mp4, .avi, .mov, .mkv)

**Response:**
```json
{
  "ok": true,
  "message": "Video processed successfully",
  "frames_used": 10,
  "embeddings_count": 1
}
```

### 2. Upload Reference Image
**Endpoint:** `POST /api/face/upload-image`

**Description:** Upload a single reference image for face recognition.

**Authentication:** Required (JWT token)

**Request:**
- Content-Type: `multipart/form-data`
- Body: `file` (image file - .jpg, .jpeg, .png)

**Response:**
```json
{
  "ok": true,
  "message": "Image processed successfully",
  "embeddings_count": 1,
  "saved_path": "/path/to/Model/ref_image.jpg"
}
```

### 3. Get Cache Status
**Endpoint:** `GET /api/face/cache-status`

**Description:** Check if face recognition embeddings are cached and ready to use.

**Authentication:** Required (JWT token)

**Response (Cached):**
```json
{
  "ok": true,
  "cached": true,
  "video_path": "my_scan.mp4",
  "model_name": "ArcFace",
  "num_frames_used": 10,
  "version": 2
}
```

**Response (Not Cached):**
```json
{
  "ok": true,
  "cached": false,
  "message": "No cache found. Please upload a reference video or image."
}
```

## Audio Streaming APIs

### 1. Start Audio Stream
**Endpoint:** `POST /api/audio/start-stream`

**Description:** Start a new audio recording session. Returns a session ID for streaming.

**Authentication:** Required (JWT token)

**Request:**
- Content-Type: `multipart/form-data`
- Body:
  - `sample_rate` (optional, default: 16000)
  - `channels` (optional, default: 1 for mono, 2 for stereo)

**Response:**
```json
{
  "ok": true,
  "session_id": "uuid-here",
  "filename": "/path/to/Model/audio_recordings/audio_uuid_timestamp.wav",
  "sample_rate": 16000,
  "channels": 1
}
```

### 2. Audio WebSocket Stream
**Endpoint:** `WebSocket /ws/audio/{session_id}`

**Description:** WebSocket endpoint for streaming audio data with optional angle information.

**Authentication:** Not required at WebSocket level (use session_id from start-stream)

**Send (Binary Audio Data):**
```
WebSocket Binary Message: raw audio bytes (16-bit PCM)
```

**Send (JSON with Angle):**
```json
{
  "audio_data": "base64-encoded-audio-bytes",
  "angle": 45.5
}
```

**Send (Stop Command):**
```json
{
  "command": "stop"
}
```

**Receive:**
```json
{
  "status": "received",
  "bytes": 1024
}
```

or

```json
{
  "status": "received",
  "angle": 45.5
}
```

### 3. Stop Audio Stream
**Endpoint:** `POST /api/audio/stop-stream/{session_id}`

**Description:** Stop an active audio recording stream.

**Authentication:** Required (JWT token)

**Response:**
```json
{
  "ok": true,
  "message": "Audio stream stopped successfully"
}
```

### 4. List Audio Recordings
**Endpoint:** `GET /api/audio/recordings`

**Description:** Get a list of all audio recordings.

**Authentication:** Required (JWT token)

**Response:**
```json
{
  "ok": true,
  "recordings": [
    "/path/to/Model/audio_recordings/audio_uuid1_timestamp1.wav",
    "/path/to/Model/audio_recordings/audio_uuid2_timestamp2.wav"
  ],
  "count": 2
}
```

### 5. Get Angle Metadata for Session
**Endpoint:** `GET /api/audio/angles/{session_id}`

**Description:** Retrieve angle data collected during an audio streaming session.

**Authentication:** Required (JWT token)

**Parameters:**
- `session_id` (path parameter): The UUID of the audio session

**Response:**
```json
{
  "ok": true,
  "session_id": "uuid-here",
  "angles": [
    {"timestamp": 0.000, "angle": 45.50},
    {"timestamp": 0.064, "angle": 46.20},
    {"timestamp": 0.128, "angle": 47.00}
  ],
  "count": 3
}
```

### 6. Download Audio File
**Endpoint:** `GET /api/audio/download/{session_id}`

**Description:** Download the recorded audio file (.wav) for a specific session.

**Authentication:** Required (JWT token)

**Parameters:**
- `session_id` (path parameter): The UUID of the audio session

**Response:**
- Binary WAV file with `Content-Type: audio/wav`
- File download with appropriate filename header

### 7. Set Desired Angle
**Endpoint:** `POST /api/audio/set-angle/{session_id}`

**Description:** Send a desired/target angle to the audio processing backend for a session.

**Authentication:** Required (JWT token)

**Parameters:**
- `session_id` (path parameter): The UUID of the audio session
- `angle` (form parameter, required): Desired angle in degrees (0-360)

**Request:**
```
POST /api/audio/set-angle/session-uuid-here
Content-Type: multipart/form-data

angle=45.5
```

**Response:**
```json
{
  "ok": true,
  "message": "Desired angle set to 45.5°",
  "session_id": "uuid-here",
  "angle": 45.5
}
```

**Error Response (Invalid Angle):**
```json
{
  "detail": "Angle must be between 0 and 360 degrees"
}
```

## File Storage

All uploaded files and processed data are stored in the `/Model/` directory:

- **Reference Videos:** `/Model/my_scan.mp4` (overwritten on each upload)
- **Reference Images:** `/Model/ref_{filename}`
- **Embeddings Cache:** `/Model/embeddings_cache.pkl`
- **Audio Recordings:** `/Model/audio_recordings/audio_{session_id}_{timestamp}.wav`
- **Audio Metadata:** `/Model/audio_recordings/audio_{session_id}_{timestamp}_metadata.txt`

## Metadata Format

Audio metadata files contain timestamp and angle data in CSV format:
```
timestamp,angle
0.000,45.50
0.064,46.20
0.128,47.00
```

## Usage Example (Python)

```python
import requests
import websockets
import asyncio

# 1. Upload reference video
with open("my_360_scan.mp4", "rb") as f:
    response = requests.post(
        "http://localhost:8000/api/face/upload-video",
        files={"file": f},
        headers={"Authorization": f"Bearer {token}"}
    )
print(response.json())

# 2. Start audio stream
response = requests.post(
    "http://localhost:8000/api/audio/start-stream",
    data={"sample_rate": 16000, "channels": 1},
    headers={"Authorization": f"Bearer {token}"}
)
session_id = response.json()["session_id"]

# 3. Stream audio via WebSocket
async def stream_audio():
    uri = f"ws://localhost:8000/ws/audio/{session_id}"
    async with websockets.connect(uri) as websocket:
        # Send audio chunk with angle
        await websocket.send(json.dumps({
            "audio_data": base64.b64encode(audio_bytes).decode(),
            "angle": 45.5
        }))
        
        # Or send raw binary
        await websocket.send(audio_bytes)
        
        # Stop when done
        await websocket.send(json.dumps({"command": "stop"}))

asyncio.run(stream_audio())

# 4. Get angle data for a session
response = requests.get(
    f"http://localhost:8000/api/audio/angles/{session_id}",
    headers={"Authorization": f"Bearer {token}"}
)
angles = response.json()["angles"]
print(f"Recorded {len(angles)} angle measurements")

# 5. Download recorded audio
response = requests.get(
    f"http://localhost:8000/api/audio/download/{session_id}",
    headers={"Authorization": f"Bearer {token}"}
)
with open("downloaded_audio.wav", "wb") as f:
    f.write(response.content)

# 6. Send desired angle to backend
response = requests.post(
    f"http://localhost:8000/api/audio/set-angle/{session_id}",
    data={"angle": 90.0},
    headers={"Authorization": f"Bearer {token}"}
)
print(response.json())
```
