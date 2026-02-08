"""
Local LLM Service using Ollama
100% free, runs locally on your machine!
"""

import os
import logging
import requests
from typing import Optional

from app.config import get_settings, SYSTEM_PROMPT

logger = logging.getLogger(__name__)


class LLMService:
    """Service for generating chat responses using local Ollama."""
    
    def __init__(self):
        self.settings = get_settings()
        # Use environment variable or default
        self.ollama_url = os.getenv("OLLAMA_URL", self.settings.ollama_url)
        self.model = "llama3.2"  # Using the model we downloaded
        self._ready = False
        
    def initialize(self):
        """Initialize and check Ollama is running."""
        try:
            # Check if Ollama is running
            response = requests.get(f"{self.ollama_url}/api/tags", timeout=2)
            if response.status_code == 200:
                logger.info("✓ Ollama service is running")
                self._ready = True
            else:
                logger.warning("Ollama service not responding properly")
        except Exception as e:
            logger.warning(f"Could not connect to Ollama: {e}")
            logger.info("Ollama will be started automatically when docker-compose runs")
    
    def is_ready(self) -> bool:
        """Check if the service is ready."""
        return self._ready
    
    async def generate_response(
        self,
        message: str,
        context: list[str],
        history: Optional[list[dict[str, str]]] = None
    ) -> str:
        """Generate a chat response with context."""
        try:
            # Build context-enhanced message
            context_text = self._build_context(context)
            full_message = f"{context_text}\n\nUser Question: {message}"
            
            # Build prompt with system message and context
            prompt = f"{SYSTEM_PROMPT}\n\n{full_message}"
            
            # Add conversation history if available
            if history:
                history_text = "\n".join([
                    f"{msg.get('role', 'user')}: {msg.get('content', '')}"
                    for msg in history[-5:]  # Keep last 5 messages
                ])
                prompt = f"{SYSTEM_PROMPT}\n\nPrevious conversation:\n{history_text}\n\n{full_message}"
            
            # Call Ollama API
            response = requests.post(
                f"{self.ollama_url}/api/generate",
                json={
                    "model": self.model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {
                        "temperature": self.settings.llm_temperature,
                        "num_predict": self.settings.llm_max_tokens
                    }
                },
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                return result.get("response", "Sorry, I couldn't generate a response.")
            else:
                logger.error(f"Ollama API error: {response.status_code}")
                return "Sorry, I encountered an error generating a response."
            
        except Exception as e:
            logger.error(f"Failed to generate response: {e}")
            return f"Sorry, I encountered an error: {str(e)}"
    
    async def generate_simple_response(self, prompt: str) -> str:
        """Generate a simple response without context."""
        try:
            response = requests.post(
                f"{self.ollama_url}/api/generate",
                json={
                    "model": self.model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {
                        "temperature": 0.7,
                        "num_predict": 500
                    }
                },
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                return result.get("response", "Sorry, I couldn't generate a response.")
            else:
                return "Sorry, I encountered an error generating a response."
            
        except Exception as e:
            logger.error(f"Failed to generate response: {e}")
            return f"Sorry, I encountered an error: {str(e)}"
    
    def _build_context(self, contexts: list[str]) -> str:
        """Build the context section of the prompt."""
        if not contexts:
            return "No relevant context found in the user's journal."
        
        context_parts = [
            "Here is relevant information from the user's personal journal and profile:\n"
        ]
        
        for i, context in enumerate(contexts, 1):
            context_parts.append(f"--- Context {i} ---\n{context}\n")
        
        context_parts.append(
            "---\n\nBased on the above context, please answer the following question. "
            "If the context doesn't contain enough information to fully answer the question, "
            "say so and provide what you can based on available information."
        )
        
        return "\n".join(context_parts)


# Singleton instance
llm_service = LLMService()
