import numpy as np
from scipy.spatial.distance import cdist
from scipy.signal import correlate
from dtaidistance import dtw  # optional, can use simple correlation
from .config import AVConfig

class PathCorrelator:
    @staticmethod
    def dynamic_time_warp(visual_angles, audio_angles):
        """Return DTW distance (lower = more similar)."""
        distance = dtw.distance(visual_angles, audio_angles)
        # Normalise to [0,1] where 1 = perfect match
        max_possible = max(len(visual_angles), len(audio_angles)) * 360.0
        similarity = 1.0 - (distance / max_possible)
        return similarity
    
    @staticmethod
    def cross_correlation_similarity(visual_angles, audio_angles):
        """Simple zero‑lag correlation after resampling to same length."""
        n = min(len(visual_angles), len(audio_angles))
        v = visual_angles[:n]
        a = audio_angles[:n]
        # Normalize
        v = (v - np.mean(v)) / (np.std(v) + 1e-6)
        a = (a - np.mean(a)) / (np.std(a) + 1e-6)
        corr = np.correlate(v, a, mode='valid')[0] / n
        return max(0.0, min(1.0, corr))
    
    @staticmethod
    def check_rhythm_match(mar_curve, rms_curve):
        """Compute correlation between lip movement and audio energy."""
        # Ensure same length
        min_len = min(len(mar_curve), len(rms_curve))
        mar = mar_curve[:min_len]
        rms = rms_curve[:min_len]
        # Normalize both to zero mean, unit variance
        mar_norm = (mar - np.mean(mar)) / (np.std(mar) + 1e-6)
        rms_norm = (rms - np.mean(rms)) / (np.std(rms) + 1e-6)
        corr = np.correlate(mar_norm, rms_norm, mode='valid')[0] / min_len
        return max(0.0, min(1.0, corr))
