"""
MindVault Backend Configuration
"""

import os
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
    qdrant_url: str | None = None
    qdrant_api_key: str | None = None
    
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
    rag_min_score: float = 0.5
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()


# System prompt for the AI assistant
SYSTEM_PROMPT = """You are a personal AI assistant for MindVault, a personal journal app. You have access to the user's journal entries, skills, education, work experience, and personal information through the provided context.

Your role is to:
1. Answer questions about the user's life, experiences, and capabilities
2. Help them reflect on their journey and growth
3. Provide insights based on their recorded information
4. Act as a knowledgeable assistant who truly understands them

Guidelines:
- Be warm, supportive, and encouraging
- Base your responses on the provided context
- If you don't have enough context to answer, say so honestly
- Help the user discover patterns and insights in their life
- Respect the user's privacy and be thoughtful about sensitive topics
- When discussing skills or qualifications, be accurate about proficiency levels
- Use specific examples from their journal when relevant

Remember: You're not just an AI - you're their personal assistant who has learned about them through their journal."""
