"""
MindVault Backend Configuration
"""

from typing import Optional
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""
    
    # No API keys needed - 100% local!
    
    # Qdrant - Local
    qdrant_host: str = "localhost"
    qdrant_port: int = 6333
    qdrant_collection: str = "mindvault"
    
    # Qdrant - Cloud (optional)
    qdrant_url: Optional[str] = None
    qdrant_api_key: Optional[str] = None
    
    # Server
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = True
    
    # Embedding - Local (sentence-transformers: all-MiniLM-L6-v2)
    embedding_model: str = "all-MiniLM-L6-v2"
    embedding_dimension: int = 384  # Changed from 1536 to 384
    
    # LLM - Local (Ollama: llama3.2)
    llm_model: str = "llama3.2"
    llm_max_tokens: int = 2000
    llm_temperature: float = 0.7
    ollama_url: str = "http://localhost:11434"
    
    # RAG
    rag_top_k: int = 5
    rag_min_score: float = 0.1  # Very low to catch generic queries like "summarize my emails"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


# System prompt for the AI assistant
SYSTEM_PROMPT = """You are MindVault, a personal AI assistant with access to the user's emails, Google Drive documents, journal entries, and profile information.

You receive CONTEXT from specialized agents that have searched the user's data. The context is labeled by source (EMAIL, DOCUMENT, JOURNAL, PROFILE).

RULES:
1. ONLY use information from the provided context. Never invent emails, documents, or entries.
2. Always cite the source: mention the email sender/subject, document filename, or journal entry date.
3. If the context contains emails, reference WHO sent them and WHEN.
4. If the context contains documents, reference WHICH document and which section.
5. If no relevant context is provided, say "I couldn't find relevant information in your data."
6. Be concise, specific, and helpful.
7. When summarizing multiple items, use a clear numbered or bulleted format."""
