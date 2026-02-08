"""
MindVault Backend - FastAPI Application
Personal AI Journal Assistant with RAG
"""

import logging
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.models import (
    EmbedRequest, EmbedResponse,
    UpsertRequest, DeleteRequest,
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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
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


# MARK: - Health Endpoints

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
    return {
        "service": "MindVault API",
        "version": "1.0.0",
        "status": "running"
    }


# MARK: - Embedding Endpoints

@app.post("/api/embed", response_model=EmbedResponse)
async def generate_embedding(request: EmbedRequest):
    """Generate an embedding for the given text."""
    try:
        embedding = await embedding_service.generate_embedding(request.text)
        return EmbedResponse(embedding=embedding)
    except Exception as e:
        logger.error(f"Embedding error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# MARK: - Vector DB Endpoints

@app.post("/api/upsert")
async def upsert_document(request: UpsertRequest):
    """Add or update a document in the vector database."""
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


@app.delete("/api/delete")
async def delete_document(request: DeleteRequest):
    """Delete a document from the vector database."""
    try:
        await rag_service.delete_document(request.id)
        return {"status": "success", "id": request.id}
    except Exception as e:
        logger.error(f"Delete error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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


# MARK: - Chat Endpoints

@app.post("/api/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Generate a chat response using RAG."""
    try:
        response, contexts = await rag_service.process_query(
            query=request.message,
            history=request.history
        )
        return ChatResponse(response=response, contexts=contexts)
    except Exception as e:
        logger.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# MARK: - Admin Endpoints

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
