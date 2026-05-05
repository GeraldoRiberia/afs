import threading
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

# your existing file (must be in same folder or PYTHONPATH)
from seld import (
    send_to_edge_device,
    start_audio_listener,
    set_global_result_dict   # <-- new import
)

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
    with lock:
        return DetectionResponse(
            label=latest_result["label"],
            angle_deg=latest_result["angle"]
        )

@app.post("/send_to_esp32")
async def send_now(esp32_ip: str = "0.0.0.0", esp32_port: int = 12345):
    if send_to_edge_device(esp32_ip, esp32_port):   # <-- pass ip/port only now
        return {"status": "sent", "data": latest_result}
    return {'status': 'none', 'data': ''}

@app.on_event("startup")
def startup_event():
    # Pass the result dict AND the lock to the listener
    set_global_result_dict(latest_result, lock)     # <-- new line
    thread = threading.Thread(
        target=start_audio_listener,
        args=(latest_result, lock),                 # <-- added lock argument
        daemon=True
    )
    thread.start()

if __name__ == "__main__":
    uvicorn.run("fastapi_app:app", host="0.0.0.0", port=8001, reload=True)