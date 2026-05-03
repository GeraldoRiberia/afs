import socket
import numpy as np
import time

UDP_IP = "0.0.0.0"
UDP_PORT = 12345

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))

print("Listening...")

while True:
    data, _ = sock.recvfrom(4096)

    samples = np.frombuffer(data, dtype=np.int16)

    left = samples[0::2]
    right = samples[1::2]

    print("L:", left[:5], "R:", right[:5])

    time.sleep(0.3) 