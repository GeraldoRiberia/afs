from pymongo import AsyncMongoClient
from bson import ObjectId
import pickle
from typing import Optional, List


class VoiceProfileStore:
    def __init__(self, users_collection):
        self.users_collection = users_collection

    async def has_voice_profile(self, face_track_id: int) -> bool:
        """Check if a voice print is stored for a given face track ID."""
        # In a real implementation, you'd have a separate collection `voice_profiles`
        # that maps face_track_id -> embedding. For simplicity, we reuse `users`
        # (but face_track_id is not the same as user_id).
        # This is a placeholder – adapt to your real DB schema.
        return False

    async def save_voice_profile(self, face_track_id: int, embedding: np.ndarray, face_crop: bytes):
        """Store embedding (pickled) and face crop in database."""
        # Example: store in `voice_profiles` collection
        pass

    async def get_voice_profile(self, face_track_id: int) -> Optional[np.ndarray]:
        """Retrieve embedding by face track ID."""
        return None

    async def find_best_match(self, embedding: np.ndarray, threshold: float) -> Optional[int]:
        """Find face_track_id whose embedding has cosine similarity > threshold."""
        # Brute‑force search over all stored embeddings – not efficient for many.
        # Use vector DB in production.
        return None
