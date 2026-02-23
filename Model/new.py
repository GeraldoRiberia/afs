import torch
import torchaudio
import numpy as np
import cv2
from ultralytics import YOLO
from deepface import DeepFace
from torchaudio.io import StreamReader
import queue
import threading

# --- CONFIGURATION ---
MODEL_NAME = "ArcFace"
DETECTOR_MODEL = "yolov8n-face.pt"
AST_MODEL_PATH = "MIT/ast-finetuned-audioset-10-10-0.4593"
MIC_DISTANCE = 0.2  # Meters between your Scarlett Solo inputs
SAMPLE_RATE = 44100

# Queues for inter-thread communication
audio_data_queue = queue.Queue(maxsize=10)
localization_queue = queue.Queue(maxsize=10)

# 1. AUDIO THREAD: AST + GCC-PHAT
def audio_processor_thread():
    from transformers import ASTForAudioClassification, ASTFeatureExtractor
    feature_extractor = ASTFeatureExtractor.from_pretrained(AST_MODEL_PATH)
    ast_model = ASTForAudioClassification.from_pretrained(AST_MODEL_PATH)
    
    streamer = StreamReader(src="audio=Scarlett Solo USB", format="avfoundation")
    streamer.add_basic_audio_stream(frames_per_chunk=2048, sample_rate=SAMPLE_RATE)
    
    for (waveform,) in streamer.stream():
        # GCC-PHAT for Spatial Localization
        mic_1, mic_2 = waveform[:, 0].numpy(), waveform[:, 1].numpy()
        n = len(mic_1) + len(mic_2)
        SIG = np.fft.rfft(mic_1, n=n)
        REFSIG = np.fft.rfft(mic_2, n=n)
        R = SIG * np.conj(REFSIG)
        cc = np.fft.irfft(R / (np.abs(R) + 1e-7), n=n)
        shift = np.argmax(cc) - (n // 2)
        
        # Calculate Angle
        delay_ratio = np.clip(shift / ((MIC_DISTANCE / 343.0) * SAMPLE_RATE), -1.0, 1.0)
        angle = np.arcsin(delay_ratio) * (180 / np.pi)
        
        # AST for Classification
        mono_audio = torch.mean(waveform, dim=1)
        inputs = feature_extractor(mono_audio, sampling_rate=SAMPLE_RATE, return_tensors="pt")
        with torch.no_grad():
            logits = ast_model(**inputs).logits
        label = ast_model.config.id2label[logits.argmax(-1).item()]
        
        # Push to main loop
        if not localization_queue.full():
            localization_queue.put({'angle': angle, 'label': label})

# 2. MAIN VISUAL THREAD: YOLO + ByteTrack + DeepFace
def main_visual_loop():
    yolo_model = YOLO(DETECTOR_MODEL)
    cap = cv2.VideoCapture(0)
    
    # Load your pre-computed master embedding here (from your cache logic)
    master_embedding = np.load("user_embedding.npy")
    
    priority_id = None
    known_tracks = {}

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret: break
        
        # Get latest Audio Info
        audio_info = None
        try: audio_info = localization_queue.get_nowait()
        except queue.Empty: pass

        # ByteTrack
        results = yolo_model.track(frame, persist=True, tracker="bytetrack.yaml", verbose=False)
        
        if results[0].boxes.id is not None:
            boxes = results[0].boxes.xyxy.cpu().numpy().astype(int)
            track_ids = results[0].boxes.id.cpu().numpy().astype(int)

            for box, track_id in zip(boxes, track_ids):
                # Check DeepFace if new track
                if track_id not in known_tracks:
                    face_crop = frame[box[1]:box[3], box[0]:box[2]]
                    try:
                        res = DeepFace.represent(face_crop, model_name=MODEL_NAME, enforce_detection=True)[0]
                        sim = np.dot(master_embedding, res["embedding"]) / (np.linalg.norm(master_embedding) * np.linalg.norm(res["embedding"]))
                        known_tracks[track_id] = (sim > 0.7)
                        if known_tracks[track_id]: priority_id = track_id
                    except: continue

                # Draw Visuals
                is_priority = (track_id == priority_id)
                color = (0, 0, 255) if is_priority else (0, 255, 0)
                cv2.rectangle(frame, (box[0], box[1]), (box[2], box[3]), color, 2)
                
                if audio_info and is_priority:
                    cv2.putText(frame, f"SPEECH: {audio_info['label']} @ {audio_info['angle']:.1f}deg", 
                                (box[0], box[1]-30), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 0, 0), 2)

        cv2.imshow("Multimodal Priority Tracker", frame)
        if cv2.waitKey(1) & 0xFF == ord('q'): break

# Start Audio Thread
threading.Thread(target=audio_processor_thread, daemon=True).start()
main_visual_loop()