# test_audio_api.py
import asyncio
import websockets
import json
import base64

# Test locally - change to HF URL when deployed
BASE_URL = "localhost:8000"
# BASE_URL = "arnavam-afs-backend.hf.space"

async def test_audio():
    session_id = "test-session-123"
    
    # WebSocket URI
    ws_protocol = "ws" if "localhost" in BASE_URL else "wss"
    uri = f"{ws_protocol}://{BASE_URL}/ws/audio/{session_id}"
    
    print(f"Connecting to {uri}...")
    
    try:
        async with websockets.connect(uri, ping_timeout=10) as ws:
            print("Connected!")
            
            # Send audio chunk with angle
            audio_bytes = b'\x00\x00' * 1000  # dummy audio data
            payload = {
                "audio_data": base64.b64encode(audio_bytes).decode(),
                "angle": 45.5
            }
            print(f"Sending audio chunk with angle {payload['angle']}...")
            await ws.send(json.dumps(payload))
            response = await ws.recv()
            print(f"Response: {response}")
            
            # Send another chunk with different angle
            payload["angle"] = 90.0
            print(f"Sending audio chunk with angle {payload['angle']}...")
            await ws.send(json.dumps(payload))
            response = await ws.recv()
            print(f"Response: {response}")
            
            # Stop stream
            print("Stopping stream...")
            await ws.send(json.dumps({"command": "stop"}))
            response = await ws.recv()
            print(f"Response: {response}")
            
    except websockets.exceptions.ConnectionClosedError as e:
        print(f"Connection closed: {e}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    asyncio.run(test_audio())
