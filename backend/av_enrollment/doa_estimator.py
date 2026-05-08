import numpy as np
import math
from scipy.signal import stft
from .config import AVConfig

class SRP_PHAT_DoA:
    """Steered‑response power phase transform for stereo direction of arrival."""
    def __init__(self, sample_rate=AVConfig.SAMPLE_RATE, mic_distance=AVConfig.MIC_DISTANCE_M):
        self.fs = sample_rate
        self.mic_distance = mic_distance
        self.speed_of_sound = AVConfig.SPEED_OF_SOUND_MPS
    
    def compute_angle(self, left_channel: np.ndarray, right_channel: np.ndarray) -> float:
        """
        Estimate angle (degrees) from stereo audio.
        Returns angle in range [-180, 180], 0 = front.
        """
        # PHAT cross‑correlation
        # This is a simplified example – real SRP‑PHAT uses GCC‑PHAT over frames
        corr = np.correlate(left_channel, right_channel, mode='full')
        lag = np.argmax(corr) - (len(corr) // 2)
        tdoa = lag / self.fs
        # angle = arcsin(tdoa * c / d)
        sin_theta = (tdoa * self.speed_of_sound) / self.mic_distance
        sin_theta = np.clip(sin_theta, -1.0, 1.0)
        angle_rad = math.asin(sin_theta)
        return math.degrees(angle_rad)
