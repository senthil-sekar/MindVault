"""
MindVault Backend - FastAPI Application
Personal AI Journal Assistant with RAG
"""

import logging
import base64
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Optional, List

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.models import (
    EmbedRequest, EmbedResponse,
    UpsertRequest, EmailUpsertRequest, DocumentUpsertRequest, DeleteRequest,
    SearchRequest, SearchResponse,
    ChatRequest, ChatResponse,
    HealthResponse
)
from app.services import (
    embedding_service,
    vector_db_service,
    llm_service,
    rag_service
)

# Agent orchestrator - lazy loaded after services are ready
_orchestrator = None

def get_orchestrator():
    """Lazy-load the agent orchestrator."""
    global _orchestrator
    if _orchestrator is None:
        from app.agents.orchestrator import agent_orchestrator
        _orchestrator = agent_orchestrator
    return _orchestrator

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    logger.info("Starting MindVault Backend...")
    
    # Initialize services
    embedding_service.initialize()
    llm_service.initialize()
    
    # Connect to Qdrant
    if not vector_db_service.connect():
        logger.error("Failed to connect to Qdrant!")
    
    logger.info("MindVault Backend started successfully")
    
    yield
    
    # Shutdown
    logger.info("Shutting down MindVault Backend...")


# Create FastAPI app
app = FastAPI(
    title="MindVault API",
    description="Backend API for MindVault Personal AI Journal Assistant",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify actual origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─────────────────────────────────────────
# MARK: - Health
# ─────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Check the health of the service."""
    return HealthResponse(
        status="ok",
        vector_db_status="connected" if vector_db_service.is_connected() else "disconnected",
        embeddings_ready=embedding_service.is_ready(),
        timestamp=datetime.utcnow()
    )


@app.get("/")
async def root():
    """Root endpoint."""
    return {"service": "MindVault API", "version": "1.0.0", "status": "running"}


# ─────────────────────────────────────────
# MARK: - Embedding
# ─────────────────────────────────────────

@app.post("/api/embed", response_model=EmbedResponse)
async def generate_embedding(request: EmbedRequest):
    """Generate an embedding for the given text."""
    try:
        embedding = await embedding_service.generate_embedding(request.text)
        return EmbedResponse(embedding=embedding)
    except Exception as e:
        logger.error(f"Embedding error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# MARK: - Upsert Endpoints
# ─────────────────────────────────────────

@app.post("/api/upsert")
async def upsert_document(request: UpsertRequest):
    """Generic upsert - used for journal entries and profile items."""
    try:
        await rag_service.upsert_document(
            id=request.id,
            content=request.content,
            metadata=request.metadata
        )
        return {"status": "success", "id": request.id}
    except Exception as e:
        logger.error(f"Upsert error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/upsert/email")
async def upsert_email(request: EmailUpsertRequest):
    """
    Upsert an email with full processing pipeline:
    1. Strip HTML / signatures / disclaimers
    2. Thread-aware chunking with Subject+Date header on each chunk
    3. Rich metadata for hybrid search
    """
    try:
        await rag_service.upsert_email(
            email_id=request.id,
            raw_content=request.content,
            subject=request.subject,
            sender=request.sender,
            date=request.date,
            thread_id=request.thread_id,
            labels=request.labels
        )
        return {"status": "success", "id": request.id}
    except Exception as e:
        logger.error(f"Email upsert error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/upsert/document")
async def upsert_drive_document(request: DocumentUpsertRequest):
    """
    Upsert a Google Drive document (PDF, DOCX, TXT) with full processing:
    1. Decode base64 content
    2. Extract text from PDF / DOCX / TXT
    3. Chunk with filename + folder context header
    4. Store in vector DB with rich metadata
    """
    try:
        from app.services.document_processor import document_processor

        # Decode base64 content
        try:
            file_bytes = base64.b64decode(request.content_base64)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid base64 content")

        # Process document into chunks
        chunks = document_processor.process_document(
            content=file_bytes,
            filename=request.filename,
            mime_type=request.mime_type,
            metadata={
                "file_id": request.file_id,
                "filename": request.filename,
                "folder_path": request.folder_path or "/",
                "source": request.source,
                "web_view_link": request.web_view_link or "",
                "modified_time": request.modified_time.isoformat() if request.modified_time else "",
                "type": "document",
            }
        )

        if not chunks:
            return {"status": "skipped", "id": request.file_id, "reason": "No text extracted"}

        # Upsert each chunk
        for i, chunk in enumerate(chunks):
            chunk_id = f"{request.file_id}_chunk_{i}"
            await rag_service.upsert_document(
                id=chunk_id,
                content=chunk["content"],
                metadata=chunk["metadata"]
            )

        logger.info(f"Upserted document '{request.filename}' as {len(chunks)} chunks")
        return {"status": "success", "id": request.file_id, "chunks": len(chunks)}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Document upsert error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# MARK: - Delete
# ─────────────────────────────────────────

@app.delete("/api/delete")
async def delete_document(request: DeleteRequest):
    """Delete a document from the vector database."""
    try:
        await rag_service.delete_document(request.id)
        return {"status": "success", "id": request.id}
    except Exception as e:
        logger.error(f"Delete error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# MARK: - Search
# ─────────────────────────────────────────

@app.post("/api/search", response_model=SearchResponse)
async def search_documents(request: SearchRequest):
    """Search for similar documents."""
    try:
        results = await rag_service.search_similar(
            query=request.query,
            top_k=request.top_k,
            filter_conditions=request.filter
        )
        return SearchResponse(results=results)
    except Exception as e:
        logger.error(f"Search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# MARK: - Chat  (routed through Agent Orchestrator)
# ─────────────────────────────────────────

@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Chat endpoint - routes through the LangGraph agent orchestrator.
    The orchestrator classifies intent and dispatches to the appropriate
    specialist agent (Email, Drive, Journal) before synthesising a response.
    """
    try:
        orchestrator = get_orchestrator()
        response, contexts = await orchestrator.process(
            query=request.message,
            history=request.history
        )
        return ChatResponse(response=response, contexts=contexts)
    except Exception as e:
        logger.error(f"Chat error: {e}", exc_info=True)
        # Graceful fallback to plain RAG
        try:
            response, contexts = await rag_service.process_query(
                query=request.message,
                history=request.history
            )
            return ChatResponse(response=response, contexts=contexts)
        except Exception as fallback_error:
            logger.error(f"Fallback chat error: {fallback_error}")
            raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# MARK: - Admin / Stats
# ─────────────────────────────────────────

@app.get("/api/stats")
async def get_stats():
    """Get collection statistics."""
    try:
        info = await vector_db_service.get_collection_info()
        return {
            "collection": info,
            "embedding_model": get_settings().embedding_model,
            "llm_model": get_settings().llm_model
        }
    except Exception as e:
        logger.error(f"Stats error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    settings = get_settings()
    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug
    )
