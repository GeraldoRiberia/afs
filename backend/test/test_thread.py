from services.single_tracker import SingleTracker
from concurrent.futures import ThreadPoolExecutor
import cv2
import asyncio

async def test():
    tracker = SingleTracker()
    frame = cv2.imread("Model/Adi.jpg")
    if frame is None:
        print("Failed to load image")
        return
        
    executor = ThreadPoolExecutor(max_workers=4)
    
    def run_inference():
        res = tracker.process_frame(frame)
        print("Tracker Output:", res)
        
    print("Running in executor...")
    await asyncio.get_event_loop().run_in_executor(executor, run_inference)
    print("Done")

if __name__ == "__main__":
    asyncio.run(test())
