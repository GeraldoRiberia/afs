import numpy as np
import cv2

class MAR_Tracker:
    """Mouth Aspect Ratio (MAR) from facial landmarks."""
    # Landmark indices for mouth (dlib / YOLO face mesh)
    # Example dlib: points 48-68
    def compute_mar(self, face_landmarks: np.ndarray) -> float:
        """
        face_landmarks: (68,2) array of (x,y) coordinates.
        Returns MAR = (vertical distance) / (horizontal distance)
        """
        if face_landmarks is None or len(face_landmarks) < 68:
            return 0.0
        # Outer mouth corners (index 48 and 54 for dlib)
        A = face_landmarks[48]   # left corner
        B = face_landmarks[54]   # right corner
        # Upper and lower lip (vertical)
        C = face_landmarks[51]   # top of upper lip
        D = face_landmarks[57]   # bottom of lower lip
        horizontal = np.linalg.norm(B - A)
        vertical = np.linalg.norm(D - C)
        if horizontal < 1e-6:
            return 0.0
        return vertical / horizontal
    
    def rhythm_profile(self, mar_history: np.ndarray) -> np.ndarray:
        """Return smoothed MAR over time (e.g., moving average)."""
        return np.convolve(mar_history, np.ones(5)/5, mode='same')
