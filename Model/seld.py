import socket
import serial
import numpy as np
import torch
import torchaudio.functional as F
from transformers import ASTForAudioClassification, ASTFeatureExtractor

# -------------------------------
# 🔥 MODEL SETUP (load once)
# -------------------------------
feature_extractor = ASTFeatureExtractor.from_pretrained(
    "MIT/ast-finetuned-audioset-10-10-0.4593"
)
model = ASTForAudioClassification.from_pretrained(
    "MIT/ast-finetuned-audioset-10-10-0.4593"
)

# -------------------------------
# 🧠 GCC-PHAT (time delay estimation)
# -------------------------------
def gcc_phat(sig, refsig, fs=16000):
    n = sig.shape[0] + refsig.shape[0]
    SIG = np.fft.rfft(sig, n=n)
    REFSIG = np.fft.rfft(refsig, n=n)
    R = SIG * np.conj(REFSIG)
    R /= (np.abs(R) + 1e-8)
    cc = np.fft.irfft(R, n=n)
    max_shift = int(n / 2)
    cc = np.concatenate((cc[-max_shift:], cc[:max_shift]))
    shift = np.argmax(np.abs(cc)) - max_shift
    return shift

# -------------------------------
# 🎯 PROCESS AUDIO (angle + classification)
# -------------------------------
def process_audio(stereo_audio, sample_rate=16000, mic_dist_meters=0.2):
    # 1. LOCALIZATION
    delay_samples = gcc_phat(stereo_audio[0], stereo_audio[1], fs=sample_rate)
    speed_of_sound = 343.0
    max_possible_delay = (mic_dist_meters / speed_of_sound) * sample_rate
    delay_ratio = np.clip(delay_samples / max_possible_delay, -1.0, 1.0)
    CALIBRATION_MAX_ANGLE = 74.7  # your pre‑measured value
    angle = np.arcsin(delay_ratio) * (180 / np.pi)
    angle = angle * (90.0 / CALIBRATION_MAX_ANGLE)

    # 2. CLASSIFICATION (mono mix)
    mono_audio = torch.mean(torch.tensor(stereo_audio), dim=0)
    inputs = feature_extractor(
        mono_audio,
        sampling_rate=sample_rate,
        return_tensors="pt"
    )
    with torch.no_grad():
        logits = model(**inputs).logits
    predicted_class_id = logits.argmax(-1).item()
    predicted_label = model.config.id2label[predicted_class_id]

    return predicted_label, angle

# -------------------------------
# 🌍 GLOBALS for send_to_edge_device (set by FastAPI startup)
# -------------------------------
_result_dict_global = None
_result_lock_global = None
_serial_conn_global = None

def set_global_result_dict(result_dict, lock):
    """Call this once from the FastAPI startup event to provide the shared state."""
    global _result_dict_global, _result_lock_global
    _result_dict_global = result_dict
    _result_lock_global = lock

def set_serial_connection(ser):
    """Call this once to set the global serial connection."""
    global _serial_conn_global
    _serial_conn_global = ser

# -------------------------------
# 📤 SEND DETECTION TO ESP32 (via Serial)
# -------------------------------
def send_to_edge_device():
    """Send the latest detection (label + angle) to the ESP32."""
    if _result_dict_global is None or _result_lock_global is None or _serial_conn_global is None:
        print("Result dict or serial connection not set.")
        return False

    with _result_lock_global:
        label = _result_dict_global.get("label")
        angle = _result_dict_global.get("angle")
        if label is None or angle is None:
            return False

    message = f"{label},{angle:.1f}\n"
    try:
        _serial_conn_global.write(message.encode())
        print(f"Sent to ESP32: {message.strip()}")
        return True
    except Exception as e:
        print(f"Failed to send: {e}")
        return False

# -------------------------------
# 🎧 AUDIO LISTENER (runs in background thread)
# -------------------------------
def start_audio_listener(result_dict, lock):
    """
    Continuously receive serial audio from ESP32, process, and update result_dict.
    Uses the provided lock for thread‑safe updates.
    """
    ESP32_SERIAL_PORT = "/dev/cu.usbmodem206EF1327F0C2"
    BAUD_RATE = 115200  # Adjust if needed
    ser = serial.Serial(ESP32_SERIAL_PORT, BAUD_RATE, timeout=1)
    print(f"Listening for ESP32 audio on serial port {ESP32_SERIAL_PORT}...")

    # Set the global serial connection for sending
    set_serial_connection(ser)

    buffer_L = []
    buffer_R = []
    TARGET_SAMPLES = 16000   # 1 sec window at 16 kHz
    HOP_SIZE = 8000          # 50% overlap
    running_max = 0.0

    try:
        while True:
            # Read a chunk of data (adjust size as needed)
            data = ser.read(4096)  # Read up to 4096 bytes
            if not data:
                continue

            # Convert bytes → int16 samples (interleaved stereo: L,R,L,R,...)
            samples = np.frombuffer(data, dtype=np.int16)
            left = samples[0::2]
            right = samples[1::2]

            buffer_L.extend(left)
            buffer_R.extend(right)

            if len(buffer_L) >= TARGET_SAMPLES:
                mic_1 = torch.tensor(buffer_L[:TARGET_SAMPLES], dtype=torch.float32)
                mic_2 = torch.tensor(buffer_R[:TARGET_SAMPLES], dtype=torch.float32)

                # Gain staging
                mic_1 = F.gain(mic_1, gain_db=6.0)
                mic_2 = F.gain(mic_2, gain_db=6.0)

                # Stable normalization (running max)
                current_max = torch.max(torch.abs(torch.stack([mic_1, mic_2]))).item()
                running_max = max(current_max, 0.9 * running_max)
                mic_1 = mic_1 / (running_max + 1e-7)
                mic_2 = mic_2 / (running_max + 1e-7)

                # Stack stereo channels
                capture = torch.stack([mic_1, mic_2], dim=0)

                # Process: classification + angle
                label, angle = process_audio(capture.numpy(), sample_rate=16000)

                # Update shared state only for Speech (or you can update always)
                if label == "Speech":
                    with lock:
                        result_dict["label"] = label
                        result_dict["angle"] = angle
                    print(f"I heard {label} at {angle:.1f} degrees!")

                # Overlap buffer for next window
                buffer_L = buffer_L[HOP_SIZE:]
                buffer_R = buffer_R[HOP_SIZE:]

    except KeyboardInterrupt:
        print("\nAudio listener stopped.")
    finally:
        ser.close()