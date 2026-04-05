import wave
import numpy as np
import logging
from pathlib import Path
from datetime import datetime

logger = logging.getLogger(__name__)

class AudioProcessor:
    def __init__(self, model_dir: str):
        self.model_dir = Path(model_dir)
        self.audio_dir = self.model_dir / "audio_recordings"
        self.audio_dir.mkdir(parents=True, exist_ok=True)
        
        self.active_streams = {}
    
    def create_audio_stream(self, session_id: str, sample_rate: int = 16000, channels: int = 1):
        """Create a new audio recording stream."""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = self.audio_dir / f"audio_{session_id}_{timestamp}.wav"
        metadata_file = self.audio_dir / f"audio_{session_id}_{timestamp}_metadata.txt"
        
        wav_file = wave.open(str(filename), 'wb')
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        
        self.active_streams[session_id] = {
            'wav_file': wav_file,
            'metadata_file': metadata_file,
            'metadata_handle': open(metadata_file, 'w'),
            'sample_rate': sample_rate,
            'channels': channels,
            'frame_count': 0
        }
        
        logger.info(f"Created audio stream {session_id} -> {filename}")
        return str(filename)
    
    def write_audio_chunk(self, session_id: str, audio_data: bytes, angle: float = None):
        """Write audio chunk with optional angle metadata."""
        if session_id not in self.active_streams:
            raise ValueError(f"No active stream for session {session_id}")
        
        stream = self.active_streams[session_id]
        stream['wav_file'].writeframes(audio_data)
        
        if angle is not None:
            timestamp = stream['frame_count'] / stream['sample_rate']
            stream['metadata_handle'].write(f"{timestamp:.3f},{angle:.2f}\n")
        
        stream['frame_count'] += len(audio_data) // (2 * stream['channels'])
    
    def close_audio_stream(self, session_id: str):
        """Close and finalize audio stream."""
        if session_id not in self.active_streams:
            raise ValueError(f"No active stream for session {session_id}")
        
        stream = self.active_streams[session_id]
        stream['wav_file'].close()
        stream['metadata_handle'].close()
        
        logger.info(f"Closed audio stream {session_id}")
        del self.active_streams[session_id]
    
    def get_audio_files(self):
        """List all audio recordings."""
        wav_files = list(self.audio_dir.glob("*.wav"))
        return [str(f) for f in sorted(wav_files, reverse=True)]
