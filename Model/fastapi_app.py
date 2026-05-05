import threading
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

# your existing file (must be in same folder or PYTHONPATH)
from seld import send_to_edge_device, start_audio_listener

# ---------- Shared state for latest detection ----------
latest_result = {
    "label": None,
    "angle": None,
}
lock = threading.Lock()

# ---------- FastAPI app ----------
app = FastAPI()


class DetectionResponse(BaseModel):
    label: str | None
    angle_deg: float | None


@app.get("/latest", response_model=DetectionResponse)
async def get_latest():
    """Get the most recent sound direction and label."""
    with lock:
        return DetectionResponse(
            label=latest_result["label"],
            angle_deg=latest_result["angle"]
        )

# You can also create an API endpoint that forces a send


@app.post("/send_to_esp32")
async def send_now(esp32_ip: str = "0.0.0.0", esp32_port: int = 12345):
    if send_to_edge_device(lock, esp32_ip, esp32_port):
        return {"status": "sent", "data": latest_result}
    return {'status': 'none', 'data': ''}

# Start the background listener when FastAPI starts


@app.on_event("startup")
def startup_event():
    thread = threading.Thread(target=start_audio_listener, args=(lock,), daemon=True)
    thread.start()

if __name__ == "__main__":
    uvicorn.run("fastapi_app:app", host="0.0.0.0", port=8001, reload=True)
