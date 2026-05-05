import socket
import numpy as np
import torch
import torchaudio.functional as F
from transformers import ASTForAudioClassification, ASTFeatureExtractor

# -------------------------------
# 🔥 MODEL SETUP
# -------------------------------
feature_extractor = ASTFeatureExtractor.from_pretrained(
    "MIT/ast-finetuned-audioset-10-10-0.4593"
)
model = ASTForAudioClassification.from_pretrained(
    "MIT/ast-finetuned-audioset-10-10-0.4593"
)

# -------------------------------
# 📡 UDP SETUP (ESP32 STREAM)
# -------------------------------
UDP_IP = "0.0.0.0"
UDP_PORT = 12345

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))

print("Listening for ESP32 audio...")

# -------------------------------
# 🧠 GCC-PHAT
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
# 🎯 PROCESS AUDIO
# -------------------------------


def process_audio(stereo_audio, sample_rate=16000, mic_dist_meters=0.2):

    # 1. LOCALIZATION
    delay_samples = gcc_phat(stereo_audio[0], stereo_audio[1], fs=sample_rate)

    speed_of_sound = 343.0
    max_possible_delay = (mic_dist_meters / speed_of_sound) * sample_rate

    delay_ratio = delay_samples / max_possible_delay
    delay_ratio = np.clip(delay_ratio, -1.0, 1.0)

    CALIBRATION_MAX_ANGLE = 74.7  # measured once

    angle = np.arcsin(delay_ratio) * (180 / np.pi)
    angle = angle * (90.0 / CALIBRATION_MAX_ANGLE)

    # 2. CLASSIFICATION
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
# 🎧 STREAMING + BUFFERING
# -------------------------------
buffer_L = []
buffer_R = []

TARGET_SAMPLES = 16000   # 1 sec window
HOP_SIZE = 8000         # 50% overlap

running_max = 0.0

while True:
    data, _ = sock.recvfrom(4096)

    # Convert bytes → int16
    samples = np.frombuffer(data, dtype=np.int16)

    # Split stereo
    left = samples[0::2]
    right = samples[1::2]

    buffer_L.extend(left)
    buffer_R.extend(right)

    # Process when enough data
    if len(buffer_L) >= TARGET_SAMPLES:

        mic_1 = torch.tensor(buffer_L[:TARGET_SAMPLES], dtype=torch.float32)
        mic_2 = torch.tensor(buffer_R[:TARGET_SAMPLES], dtype=torch.float32)

        # 🎚 Gain
        mic_1 = F.gain(mic_1, gain_db=6.0)
        mic_2 = F.gain(mic_2, gain_db=6.0)

        # 🔄 Stable normalization
        current_max = torch.max(torch.abs(torch.stack([mic_1, mic_2]))).item()
        running_max = max(current_max, 0.9 * running_max)

        mic_1 = mic_1 / (running_max + 1e-7)
        mic_2 = mic_2 / (running_max + 1e-7)

        # 🎧 Stack stereo
        capture = torch.stack([mic_1, mic_2], dim=0)

        # 🔥 PROCESS
        label, angle = process_audio(capture.numpy(), 16000)

        if label == "Speech":
            print(f"I heard a {label} at {angle:.1f} degrees!")

        # 🔁 Overlap buffer (performance boost)
        buffer_L = buffer_L[HOP_SIZE:]
        buffer_R = buffer_R[HOP_SIZE:]
