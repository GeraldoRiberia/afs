<<<<<<< Updated upstream
from transformers import ASTForAudioClassification, ASTFeatureExtractor
import torchaudio.functional as F
from torchaudio.io import StreamReader
from scipy.spatial.distance import euclidean
import numpy as np
import torchaudio
import torch
import os
os.environ['TORCHAUDIO_USE_SOX_IO_BACKEND'] = '0'  # Use FFmpeg backend


streamer = StreamReader(
    src="audio=Scarlett Solo USB",
    format="avfoundation",  # Change to "avfoundation" for Mac
    option={"channels": "2", "sample_rate": "44100"}
=======
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
>>>>>>> Stashed changes
)
model = ASTForAudioClassification.from_pretrained(
    "MIT/ast-finetuned-audioset-10-10-0.4593"
)

# -------------------------------
# 📡 UDP SETUP (ESP32 STREAM)
# -------------------------------
UDP_IP = "0.0.0.0"
UDP_PORT = 12345

<<<<<<< Updated upstream
def process_audio(stereo_audio, sample_rate, mic_dist_meters=0.2):
    # 1. LOCALIZATION
    delay_samples = gcc_phat(stereo_audio[0], stereo_audio[1], fs=sample_rate)

    # Convert delay to Angle (The "1D" Localization)
    speed_of_sound = 343.0
    max_possible_delay = (mic_dist_meters / speed_of_sound) * sample_rate

    # Clamp value to avoid arcsin errors
    delay_ratio = delay_samples / max_possible_delay
    delay_ratio = np.clip(delay_ratio, -1.0, 1.0)

    # Calculate Angle (0 is center, -90 is left, +90 is right)
    angle = np.arcsin(delay_ratio) * (180 / np.pi)


    return angle
# Running maximum for smooth normalization (prevents gain pumping)
running_max = 0.0

for (waveform,) in streamer.stream():
    # waveform shape is [1024, 2] -> (time, channels)

    # SPLIT CHANNELS
    mic_1 = waveform[:, 0]  # Input 1
    mic_2 = waveform[:, 1]  # Input 2

    # Apply gain staging
    mic_1_boosted = F.gain(mic_1, gain_db=6.0)
    mic_2_boosted = F.gain(mic_2, gain_db=6.0)

    # Zero-latency normalization with running maximum (smoothing factor 0.9)
    current_max = torch.max(
        torch.abs(torch.stack([mic_1_boosted, mic_2_boosted]))).item()
    running_max = max(current_max, 0.9 * running_max)

    # Normalize to prevent clipping (epsilon prevents division by zero)
    mic_1_normalized = mic_1_boosted / (running_max + 1e-7)
    mic_2_normalized = mic_2_boosted / (running_max + 1e-7)

    # Stack channels for processing: shape [2, 1024]
    capture = torch.stack([mic_1_normalized, mic_2_normalized], dim=0)

    # Process audio immediately (zero latency)
    angle = process_audio(capture.numpy(), 44100)
    print(f"I heard at {angle:.1f} degrees!")

# GCC PHAT implementation


def gcc_phat(sig, refsig, fs=44100, max_tau=None):
    # This function finds the delay between two signals
    n = sig.shape[0] + refsig.shape[0]

    # Generalized Cross Correlation
    SIG = np.fft.rfft(sig, n=n)
    REFSIG = np.fft.rfft(refsig, n=n)
    R = SIG * np.conj(REFSIG)
    cc = np.fft.irfft(R / np.abs(R), n=n)

    # Find the peak (the delay)
    max_shift = int(np.floor(n / 2))
    cc = np.concatenate((cc[-max_shift:], cc[:max_shift+1]))
    shift = np.argmax(cc) - max_shift
    return shift  # Returns delay in samples


=======
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
>>>>>>> Stashed changes

# -------------------------------
# 🎧 STREAMING + BUFFERING
# -------------------------------
buffer_L = []
buffer_R = []

<<<<<<< Updated upstream
# The streaming loop above processes audio in real-time
# No need for separate capture_live_audio() call
=======
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
>>>>>>> Stashed changes
