import numpy as np
import torchaudio
import torch
from speechbrain.pretrained import EncoderClassifier
from deepfilternet import DeepFilterNet  # optional

class VoiceEnroller:
    def __init__(self):
        self.embedder = None
        self.denoiser = None
        self._load_models()
    
    def _load_models(self):
        # Load ECAPA-TDNN from SpeechBrain
        self.embedder = EncoderClassifier.from_hparams(
            source="speechbrain/spkrec-ecapa-voxceleb",
            savedir="tmp_speechbrain"
        )
        # Load DeepFilterNet for denoising (optional)
        # self.denoiser = DeepFilterNet()
    
    def denoise(self, audio: np.ndarray, sample_rate: int) -> np.ndarray:
        """Apply DeepFilterNet to clean audio."""
        if self.denoiser:
            # Simplified placeholder
            return audio
        return audio
    
    def extract_embedding(self, audio: np.ndarray, sample_rate: int) -> np.ndarray:
        """Return ECAPA‑TDNN embedding (voice print) as 1D numpy array."""
        # Convert to torch tensor (mono, float)
        if audio.ndim == 2:
            audio = audio[:, 0]  # take left channel
        audio_tensor = torch.from_numpy(audio).float()
        # Resample to 16kHz if needed
        if sample_rate != 16000:
            resampler = torchaudio.transforms.Resample(sample_rate, 16000)
            audio_tensor = resampler(audio_tensor)
        # Forward through SpeechBrain
        with torch.no_grad():
            embedding = self.embedder.encode_batch(audio_tensor.unsqueeze(0))
        return embedding.squeeze().cpu().numpy()
    
    def compare_embeddings(self, emb1: np.ndarray, emb2: np.ndarray) -> float:
        """Cosine similarity between two embeddings."""
        from sklearn.metrics.pairwise import cosine_similarity
        return cosine_similarity(emb1.reshape(1, -1), emb2.reshape(1, -1))[0][0]
