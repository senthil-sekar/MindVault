"""
Local Embedding Service using Sentence Transformers
100% free, runs locally on your machine!
"""

import logging
from typing import Optional, List
from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)


class EmbeddingService:
    """Service for generating text embeddings locally using Sentence Transformers."""
    
    def __init__(self):
        self.model: Optional[SentenceTransformer] = None
        self.embedding_dimension = 384  # all-MiniLM-L6-v2 dimension
        
    def initialize(self):
        """Initialize the local embedding model."""
        try:
            logger.info("Loading local embedding model: all-MiniLM-L6-v2...")
            # Using all-MiniLM-L6-v2: Fast, efficient, 384-dimensional embeddings
            # ~80MB model, runs on CPU, perfect for personal use
            self.model = SentenceTransformer('all-MiniLM-L6-v2')
            logger.info("✓ Local embedding model loaded successfully!")
        except Exception as e:
            logger.error(f"Failed to load embedding model: {e}")
            raise
    
    def is_ready(self) -> bool:
        """Check if the service is ready."""
        return self.model is not None
    
    async def generate_embedding(self, text: str) -> List[float]:
        """Generate an embedding for the given text."""
        if not self.model:
            raise RuntimeError("Embedding model not initialized")
        
        try:
            # Clean and truncate text
            cleaned_text = self._prepare_text(text)
            
            # Generate embedding using local model
            embedding = self.model.encode(cleaned_text, convert_to_numpy=True)
            
            logger.debug(f"Generated embedding of dimension {len(embedding)}")
            return embedding.tolist()
            
        except Exception as e:
            logger.error(f"Failed to generate embedding: {e}")
            raise
    
    def _prepare_text(self, text: str, max_length: int = 8000) -> str:
        """Clean and truncate text for embedding."""
        # Remove excessive whitespace
        import re
        cleaned = re.sub(r'\s+', ' ', text).strip()
        
        # Truncate if too long
        if len(cleaned) > max_length:
            cleaned = cleaned[:max_length]
            # Try to end at a sentence boundary
            last_period = cleaned.rfind('.')
            if last_period > max_length * 0.8:
                cleaned = cleaned[:last_period + 1]
        
        return cleaned


# Singleton instance
embedding_service = EmbeddingService()
