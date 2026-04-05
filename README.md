# AFS (Auto Framing Software)

## Project Intent and Context
AFS (Auto Framing Software) is an AI-powered camera tracking and framing application. It acts as an automated camera operator by utilizing a Flutter frontend to capture video and a Python backend (FastAPI) to perform real-time tracking inference (YOLOv8, DeepFace, OpenCV). The backend tracks targets (single person or multiple people), applies exponential moving average (EMA) for smooth camera panning and zooming (Center Stage), and streams the framed result back or over to OBS (via MJPEG) and virtual cameras.

This system is designed to provide high-quality framing for broadcasts, streams, or recordings without the need for manual camera operation.

## Folder Structure

- `/afs` - **Flutter Frontend Application**
  - Built with Dart and Flutter (cross-platform: macOS, Android/iOS, Windows).
  - Handles UI (HUD, controls, auth screens) and accesses local hardware cameras.
  - Communicates with the backend using WebSockets for low-latency frame processing and HTTP for authentication.
  - `/afs/lib`: Contains all Dart code (UI, Auth Services, Theme).
    - `services/auth_service.dart`: Authentication management with JWT using `flutter_secure_storage`.
    - `screens/`: App pages including login, signup, onboarding, and settings.
    - `main.dart`: Contains the core camera capture and websocket streaming logic.

- `/backend` - **Python FastAPI Backend**
  - Powered by FastAPI, WebSockets, OpenCV, and Ultralytics (YOLO).
  - Uses `motor` (AsyncIOMotorClient) for asynchronous MongoDB interactions (for users).
  - Implements JWT generation and verification using `passlib` and `jose`.
  - `/backend/server.py`: Primary entrypoint. Handles HTTP routes (auth, OBS feed) and WebSocket endpoints (frame stream).
  - `/backend/services`: Tracker implementations (`single_tracker.py`, `multi_tracker.py`).
  - `/backend/test`: Contains test files for OpenCV, WebSockets, etc.

- `/Model` - **Machine Learning Models & Prototyping**
  - Contains research, prototypes, object tracking scripts, audio streaming tests, and raw model files like `yolov8n-face.pt`.

## Architecture & Communication
1. **Authentication:** The frontend uses HTTP POST to `/auth/login` or `/auth/register` to receive a JWT. The token is securely stored via `flutter_secure_storage`.
2. **Video Streaming:** The frontend connects via WebSocket (`/ws`) to `backend/server.py`. It continuously sends JPEG-encoded frames (converted to byte arrays) from the camera to the backend.
3. **Inference & Auto-framing:** The backend performs inference (either "single" or "multi" mode) via ThreadPoolExecutor to prevent event loop blocking. It computes a bounding box, applies Center Stage smoothing (EMA), and returns coordinate tracking data back to the frontend.
4. **Recording/OBS:** The backend can also record cropped frames directly to MP4 or output a stream via an HTTP `/obs_feed` endpoint that OBS Studio can consume as a Media Source.

## Setup & Execution

### Prerequisites
- Flutter SDK (^3.9.2)
- Python 3.10+
- MongoDB (running locally or accessible via URI)

### Running the Backend
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export MONGODB_URI="mongodb://localhost:27017"
export MONGODB_DB="afs"
export JWT_SECRET_KEY="your-secret-key"
python server.py  # or uvicorn server:app --host 0.0.0.0 --port 8000
```

### Running the Frontend
```bash
cd afs
flutter pub get
flutter run -d macos  # or your preferred device
```

## Developer Notes for Future AI Agents
- **Style Guidelines:** Follow the sleek "Matte Obsidian" aesthetic for UI updates. Use variables from `afs/lib/theme.dart`.
- **Database:** Ensure async MongoDB approaches are used (`motor`). The backend server uses it via `AsyncIOMotorClient`.
- **State Management:** Flutter state is currently managed locally using `setState` and standard callbacks. Keep this simple unless a global state manager is explicitly requested.
- **Isolates:** Heavy image processing (e.g., converting camera frames to JPEG) in Flutter happens within Isolates (`compute()`) to avoid dropping UI frames. Maintain this paradigm for performance.
- **Virtual Camera:** Support for virtual cameras (like macOS/linux VCam plugins) is implemented/prototyped on the backend side, continuously pushing frames.
