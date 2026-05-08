import numpy as np
from typing import Literal

class FalconOSD:
    """Detects if audio contains single or multiple speakers."""
    def __init__(self, access_key: str, model_path: str):
        self.access_key = access_key
        self.model_path = model_path
        # In production: Picovoice Falcon
    
    def predict(self, audio_chunk: np.ndarray) -> Literal["single", "multiple"]:
        """Return 'single' if only one speaker, else 'multiple'."""
        # Placeholder
        return "single"
