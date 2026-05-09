import serial
import numpy as np

# CHANGE THIS to your ESP32 serial port
PORT = "/dev/cu.usbmodem206EF1327F0C2"

BAUD = 921600

ser = serial.Serial(PORT, BAUD)

print("Listening for ESP32 audio...")

while True:

    # Read raw bytes
    data = ser.read(2048)

    # Convert bytes → int16 audio
    samples = np.frombuffer(data, dtype=np.int16)

    if len(samples) < 2:
        continue

    # Stereo split
    left = samples[0::2]
    right = samples[1::2]

    # Audio levels
    left_level = np.mean(np.abs(left))
    right_level = np.mean(np.abs(right))

    print(
        f"L: {left_level:.1f} | R: {right_level:.1f}"
    )