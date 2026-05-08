import asyncio
import numpy as np
from collections import deque
from typing import Optional, Tuple
import logging
from .config import AVConfig
from .gatekeeper import CobraGatekeeper
from .overlapped_detector import FalconOSD
from .doa_estimator import SRP_PHAT_DoA
from .mouth_tracker import MAR_Tracker
from .path_validator import PathCorrelator
from .voice_enroller import VoiceEnroller
from .profile_store import VoiceProfileStore
from .models import EnrollmentStatus, AudioVisualPath

logger = logging.getLogger(__name__)

class AVEnrollmentOrchestrator:
    """Implements Phases 0‑6 of the PDF workflow."""
    def __init__(self, profile_store: VoiceProfileStore):
        self.profile_store = profile_store
        self.vad = CobraGatekeeper(AVConfig.COBRA_ACCESS_KEY, AVConfig.COBRA_MODEL_PATH)
        self.overlap = FalconOSD(AVConfig.COBRA_ACCESS_KEY, AVConfig.FALCON_MODEL_PATH)
        self.doa = SRP_PHAT_DoA()
        self.mar = MAR_Tracker()
        self.enroller = VoiceEnroller()
        self.correlator = PathCorrelator()
        
        self.current_session: Optional[EnrollmentSession] = None
        self.status = EnrollmentStatus.IDLE
        
        # Circular buffers for building path (1.5 seconds at 30 fps, 16kHz audio)
        self.visual_buffer = deque(maxlen=int(30 * AVConfig.DTW_WINDOW_SEC))
        self.audio_left_buffer = deque(maxlen=int(AVConfig.SAMPLE_RATE * AVConfig.DTW_WINDOW_SEC))
        self.audio_right_buffer = deque(maxlen=int(AVConfig.SAMPLE_RATE * AVConfig.DTW_WINDOW_SEC))
        self.timestamps = deque(maxlen=int(30 * AVConfig.DTW_WINDOW_SEC))
        self.mar_buffer = deque(maxlen=int(30 * AVConfig.DTW_WINDOW_SEC))
        self.rms_buffer = deque(maxlen=int(30 * AVConfig.DTW_WINDOW_SEC))
        
    async def process_frame(self, frame: np.ndarray, face_boxes: list, face_landmarks: list, timestamp: float):
        """
        Called for each video frame during active enrollment.
        face_boxes: list of (x1,y1,x2,y2) in pixel coordinates.
        face_landmarks: list of landmark arrays (68 points) for each face.
        """
        if self.status not in (EnrollmentStatus.BUILDING_PATH, EnrollmentStatus.VERIFYING_SPEAKER_COUNT):
            return
        
        # For simplicity, assume we have exactly one candidate face (the unregistered one)
        # or use the provided Track ID from server.
        if not face_boxes:
            return
        
        # Convert bounding box to visual angle
        h, w = frame.shape[:2]
        box = face_boxes[0]  # candidate
        cx = (box[0] + box[2]) / 2.0
        vis_angle = (cx / w - 0.5) * 90.0   # assuming 90° FoV
        self.visual_buffer.append(vis_angle)
        self.timestamps.append(timestamp)
        
        # MAR from landmarks
        if face_landmarks:
            mar_val = self.mar.compute_mar(face_landmarks[0])
            self.mar_buffer.append(mar_val)
    
    async def feed_audio(self, left_channel: np.ndarray, right_channel: np.ndarray):
        """Push audio chunks into buffers. Called from WebSocket."""
        if self.status != EnrollmentStatus.BUILDING_PATH:
            return
        self.audio_left_buffer.extend(left_channel)
        self.audio_right_buffer.extend(right_channel)
        # Compute RMS for rhythm matching
        rms = np.sqrt(np.mean(left_channel**2))
        self.rms_buffer.append(rms)
    
    async def start_enrollment_for_face(self, face_track_id: int):
        """Initiate Phase 0. Called when an unregistered face is detected."""
        # Check if already enrolled (Phase 0)
        has_profile = await self.profile_store.has_voice_profile(face_track_id)
        if has_profile:
            logger.info(f"Face {face_track_id} already has voice profile – skipping enrollment")
            return False
        
        self.current_session = EnrollmentSession(face_track_id=face_track_id)
        self.status = EnrollmentStatus.WAITING_SPEECH
        logger.info(f"Enrollment started for face {face_track_id}, waiting for speech")
        return True
    
    async def run(self):
        """Main state machine loop (run as background task)."""
        while True:
            if self.status == EnrollmentStatus.WAITING_SPEECH:
                # Phase 1: VAD gatekeeper
                # In practice, audio chunks are fed as they arrive.
                # We'll rely on `feed_audio` to trigger transition when VAD fires.
                await asyncio.sleep(0.05)
            
            elif self.status == EnrollmentStatus.VERIFYING_SPEAKER_COUNT:
                # Phase 3: Falcon OSD on the audio buffer (first 200ms)
                # Extract 200ms from audio buffers
                if len(self.audio_left_buffer) < 3200:  # 200ms at 16kHz
                    await asyncio.sleep(0.05)
                    continue
                audio_200ms = np.array(self.audio_left_buffer)[:3200]
                verdict = self.overlap.predict(audio_200ms)
                if verdict == "multiple":
                    logger.info("Multiple speakers detected – aborting and resetting")
                    self.reset_buffers()
                    self.status = EnrollmentStatus.WAITING_SPEECH
                else:
                    self.status = EnrollmentStatus.BUILDING_PATH
                    logger.info("Single speaker – proceeding to build path")
            
            elif self.status == EnrollmentStatus.BUILDING_PATH:
                # Wait until we have enough data (1.5 seconds)
                required_frames = int(30 * AVConfig.DTW_WINDOW_SEC)
                required_audio_samples = int(AVConfig.SAMPLE_RATE * AVConfig.DTW_WINDOW_SEC)
                if (len(self.visual_buffer) < required_frames or 
                    len(self.audio_left_buffer) < required_audio_samples):
                    await asyncio.sleep(0.05)
                    continue
                
                # Phase 4: Path validation
                vis_angles = list(self.visual_buffer)
                # Compute audio angles for each time window (e.g., every 0.1s)
                audio_angles = []
                step = int(0.1 * AVConfig.SAMPLE_RATE)  # 100ms windows
                left_arr = np.array(self.audio_left_buffer)
                right_arr = np.array(self.audio_right_buffer)
                for start in range(0, len(left_arr) - step, step):
                    left_chunk = left_arr[start:start+step]
                    right_chunk = right_arr[start:start+step]
                    angle = self.doa.compute_angle(left_chunk, right_chunk)
                    audio_angles.append(angle)
                # Interpolate visual angles to same timestamps
                # (Simplified: just take one angle per 100ms)
                vis_interp = []
                for i in range(len(audio_angles)):
                    idx = int(i * step / (AVConfig.SAMPLE_RATE / 30))  # very rough
                    if idx < len(vis_angles):
                        vis_interp.append(vis_angles[idx])
                    else:
                        vis_interp.append(vis_angles[-1])
                
                # Correlation
                corr_score = self.correlator.cross_correlation_similarity(vis_interp, audio_angles)
                # Also check rhythm
                mar_arr = np.array(self.mar_buffer)
                rms_arr = np.array(self.rms_buffer)
                rhythm_score = self.correlator.check_rhythm_match(mar_arr, rms_arr)
                # Path correlation threshold
                if corr_score >= AVConfig.CORRELATION_THRESHOLD and rhythm_score >= 0.7:
                    logger.info(f"Path correlation passed: {corr_score:.2f}, rhythm: {rhythm_score:.2f}")
                    self.status = EnrollmentStatus.ENROLLING
                else:
                    logger.info(f"Path correlation failed: {corr_score:.2f}, rhythm: {rhythm_score:.2f} – resetting")
                    self.reset_buffers()
                    self.status = EnrollmentStatus.WAITING_SPEECH
            
            elif self.status == EnrollmentStatus.ENROLLING:
                # Phase 5: Voice print enrollment
                # Extract clean 1.5-2 sec audio from buffers
                duration = min(AVConfig.MAX_ENROLL_SEC, AVConfig.DTW_WINDOW_SEC)
                samples = int(duration * AVConfig.SAMPLE_RATE)
                audio_clean = np.array(self.audio_left_buffer)[:samples]
                # Denoise
                audio_clean = self.enroller.denoise(audio_clean, AVConfig.SAMPLE_RATE)
                # Extract embedding
                embedding = self.enroller.extract_embedding(audio_clean, AVConfig.SAMPLE_RATE)
                # Save to DB
                await self.profile_store.save_voice_profile(self.current_session.face_track_id, embedding, b"")
                self.status = EnrollmentStatus.ENROLLED
                logger.info(f"Enrollment complete for face {self.current_session.face_track_id}")
                self.reset_buffers()
                # Go idle until next unregistered face
                self.status = EnrollmentStatus.IDLE
                self.current_session = None
    
    def reset_buffers(self):
        self.visual_buffer.clear()
        self.audio_left_buffer.clear()
        self.audio_right_buffer.clear()
        self.timestamps.clear()
        self.mar_buffer.clear()
        self.rms_buffer.clear()
