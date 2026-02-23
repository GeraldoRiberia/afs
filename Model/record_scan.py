import cv2
import time

OUTPUT_FILE = "my_scan.mp4"
FRAME_RATE = 30.0
RESOLUTION = (640, 480)

def record_scan():
    cap = cv2.VideoCapture(2) # Use 0 for default webcam, change to 1 or 2 if needed
    
    # Check if camera opened successfully
    if not cap.isOpened():
        print("Error: Could not open camera.")
        return

    # Get actual resolution from camera
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    resolution = (width, height)
    print(f"Camera Resolution: {width}x{height}")

    # Define the codec and create VideoWriter object
    # On macOS, 'avc1' or 'h264' is often more reliable than 'mp4v'
    fourcc = cv2.VideoWriter_fourcc(*'avc1') 
    out = None
    is_recording = False
    
    print(f"--- Video Scan Recorder ---")
    print(f"Press 's' to START recording.")
    print(f"Press 'q' to STOP and QUIT.")
    print(f"Output will be saved to: {OUTPUT_FILE}")

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            print("Failed to receive frame")
            break

        # Display the frame
        display_frame = frame.copy()
        
        if is_recording:
            # unique visual indicator for recording
            cv2.circle(display_frame, (30, 30), 10, (0, 0, 255), -1) 
            cv2.putText(display_frame, "REC", (50, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
            
            if out is not None:
                out.write(frame)
        else:
             cv2.putText(display_frame, "Press 's' to Start", (10, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 0), 2)

        cv2.imshow('Record Scan', display_frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('s'):
            if not is_recording:
                is_recording = True
                out = cv2.VideoWriter(OUTPUT_FILE, fourcc, FRAME_RATE, resolution)
                print("Recording STARTED...")
            else:
                 print("Already recording.")

    # Release everything if job is finished
    cap.release()
    if out is not None:
        out.release()
    cv2.destroyAllWindows()
    print(f"Done. Saved to {OUTPUT_FILE}")

if __name__ == "__main__":
    record_scan()
