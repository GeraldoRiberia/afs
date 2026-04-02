import asyncio
import websockets
import json
import cv2

async def test():
    async with websockets.connect("ws://localhost:8000/ws") as ws:
        cap = cv2.VideoCapture("Model/my_scan.mp4")
        for i in range(15):
            ret, frame = cap.read()
            if not ret: break
            ret, buffer = cv2.imencode('.jpg', frame)
            await ws.send(buffer.tobytes())
            res = await ws.recv()
            print("Received:", res)

asyncio.run(test())
