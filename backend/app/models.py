"""
Pydantic models for API requests and responses.
"""

from pydantic import BaseModel, Field
from typing import Optional, Any, List, Dict
from datetime import datetime


# MARK: - Embedding Models

class EmbedRequest(BaseModel):
    """Request to generate an embedding for text."""
    text: str = Field(..., min_length=1, max_length=50000)


class EmbedResponse(BaseModel):
    """Response containing the generated embedding."""
    embedding: List[float]
    id: Optional[str] = None


# MARK: - Vector DB Models

class UpsertRequest(BaseModel):
    """Request to upsert a document into the vector DB."""
    id: str
    content: str = Field(..., min_length=1)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class DeleteRequest(BaseModel):
    """Request to delete a document from the vector DB."""
    id: str


class SearchRequest(BaseModel):
    """Request to search the vector DB."""
    query: str = Field(..., min_length=1)
    top_k: int = Field(default=5, ge=1, le=20)
    filter: Optional[Dict[str, Any]] = None


class SearchResult(BaseModel):
    """A single search result."""
    id: str
    score: float
    metadata: Dict[str, Any]
    content: Optional[str] = None


class SearchResponse(BaseModel):
    """Response containing search results."""
    results: List[SearchResult]


# MARK: - Chat Models

class ChatMessage(BaseModel):
    """A single chat message."""
    role: str = Field(..., pattern="^(user|assistant|system)$")
    content: str


class ChatRequest(BaseModel):
    """Request to generate a chat response."""
    message: str = Field(..., min_length=1)
    history: Optional[List[Dict[str, str]]] = None


class ContextResult(BaseModel):
    """Context retrieved for a chat response."""
    id: str
    type: str
    title: str
    snippet: str
    score: float


class ChatResponse(BaseModel):
    """Response containing the chat response and context."""
    response: str
    contexts: List[ContextResult]


# MARK: - Health Models

class HealthResponse(BaseModel):
    """Response for health check endpoint."""
    status: str
    vector_db_status: str
    embeddings_ready: bool
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# MARK: - Document Models

class JournalEntryMetadata(BaseModel):
    """Metadata for a journal entry."""
    id: str
    type: str = "journal_entry"
    category: str
    tags: List[str] = Field(default_factory=list)
    created_at: str
    title: str


class ProfileItemMetadata(BaseModel):
    """Metadata for a profile item."""
    id: str
    type: str
    title: str
    proficiency: Optional[int] = None
    tags: List[str] = Field(default_factory=list)
    is_current: bool = False
