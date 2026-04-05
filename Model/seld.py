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
)
streamer.add_basic_audio_stream(
    frames_per_chunk=1024,
    sample_rate=44100
)

print("Streaming started...")

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




# The streaming loop above processes audio in real-time
# No need for separate capture_live_audio() call
