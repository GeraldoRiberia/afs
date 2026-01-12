import torch
import numpy as np
import sounddevice as sd
import torchaudio.functional as F

print("Starting audio test...")

# Audio configuration
SAMPLE_RATE = 44100
CHUNK_SIZE = 1024
CHANNELS = 2

# Running maximum for smooth normalization (prevents gain pumping)
running_max = 0.0

def audio_callback(indata, frames, time, status):
    global running_max
    
    if status:
        print(f"Status: {status}")
    
    # indata shape is [frames, channels] -> (1024, 2)
    # Convert to torch tensor
    waveform = torch.from_numpy(indata.copy()).float()
    
    # SPLIT CHANNELS
    mic_1 = waveform[:, 0] # Input 1
    mic_2 = waveform[:, 1] # Input 2
    
    # Apply gain staging
    mic_1_boosted = F.gain(mic_1, gain_db=6.0)
    mic_2_boosted = F.gain(mic_2, gain_db=6.0)
    
    # Zero-latency normalization with running maximum (smoothing factor 0.9)
    current_max = torch.max(torch.abs(torch.stack([mic_1_boosted, mic_2_boosted]))).item()
    running_max = max(current_max, 0.9 * running_max)
    
    # Normalize to prevent clipping (epsilon prevents division by zero)
    mic_1_normalized = mic_1_boosted / (running_max + 1e-7)
    mic_2_normalized = mic_2_boosted / (running_max + 1e-7)
    
    # Stack channels for processing: shape [2, 1024]
    capture = torch.stack([mic_1_normalized, mic_2_normalized], dim=0)
    
    # Print audio levels
    print(f"Mic 1 level: {torch.max(torch.abs(mic_1)).item():.4f}, Mic 2 level: {torch.max(torch.abs(mic_2)).item():.4f}, Running max: {running_max:.4f}")


# List available audio devices with details
print("\n--- Audio Devices ---")
devices = sd.query_devices()
input_devices = []
for i, device in enumerate(devices):
    print(f"Index {i}: {device['name']} (Inputs: {device['max_input_channels']}, Outputs: {device['max_output_channels']})")
    if device['max_input_channels'] > 0:
        input_devices.append((i, device))

# Find Scarlett Solo USB device
scarlett_index = None
for i, device in enumerate(devices):
    if "Scarlett Solo USB" in device['name'] and device['max_input_channels'] > 0:
        scarlett_index = i
        print(f"\n-> Found Scarlett Solo USB at index {i}")
        break

if scarlett_index is None:
    print("\nWarning: Scarlett Solo USB not found or has no inputs.")
    
    if len(input_devices) > 0:
        # Default to the first valid input device (often index 0 or 1 on Mac)
        # On Mac, index 0 is often just the default system setting pointer
        scarlett_index = input_devices[0][0]
        print(f"-> Using first available input device: {input_devices[0][1]['name']} (Index {scarlett_index})")
    else:
        print("Error: No input devices found!")
        exit(1)

print(f"\nStreaming started from device {scarlett_index}...")
print("Press Ctrl+C to stop.\n")

# Start streaming
try:
    with sd.InputStream(
        device=scarlett_index,
        channels=CHANNELS,
        samplerate=SAMPLE_RATE,
        blocksize=CHUNK_SIZE,
        callback=audio_callback
    ):
        # Keep the stream running
        sd.sleep(int(1e9))  # Sleep for a very long time
except KeyboardInterrupt:
    print("\nStreaming stopped.")
except Exception as e:
    print(f"\nError: {e}")
