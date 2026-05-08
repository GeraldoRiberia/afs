import numpy as np
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class CobraGatekeeper:
    """Always‑on VAD – detects human speech with minimal CPU."""
    def __init__(self, access_key: str, model_path: str):
        self.access_key = access_key
        self.model_path = model_path
        self._vad = None
        # In production: initialize Picovoice Cobra
        # from pvleopard import create
        # self._vad = create(access_key=access_key, model_path=model_path)
    
    def is_human_speech(self, audio_chunk: np.ndarray) -> bool:
        """Returns True if probability of human speech > 80%."""
        # Placeholder: always return False if not implemented
        # Replace with actual Cobra inference
        logger.debug("Cobra VAD called – placeholder returning False")
        return False
    
    def reset(self):
        """Reset internal state if needed."""
        pass
