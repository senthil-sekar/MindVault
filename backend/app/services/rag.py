"""
RAG (Retrieval-Augmented Generation) Service
Orchestrates embedding, search, and LLM for answering questions.
"""

import logging
from typing import Optional

from app.services.embedding import embedding_service
from app.services.vector_db import vector_db_service
from app.services.llm import llm_service
from app.models import SearchResult, ContextResult
from app.config import get_settings

logger = logging.getLogger(__name__)


class RAGService:
    """Orchestrates RAG pipeline for answering questions."""
    
    def __init__(self):
        self.settings = get_settings()
    
    async def process_query(
        self,
        query: str,
        history: Optional[list[dict[str, str]]] = None
    ) -> tuple[str, list[ContextResult]]:
        """
        Process a user query using RAG.
        
        1. Generate embedding for the query
        2. Search for relevant documents
        3. Generate response with context
        
        Returns:
            Tuple of (response_text, list of contexts used)
        """
        try:
            # Step 1: Generate query embedding
            logger.info(f"Processing query: {query[:100]}...")
            query_embedding = await embedding_service.generate_embedding(query)
            
            # Step 2: Search for relevant documents
            search_results = await vector_db_service.search(
                vector=query_embedding,
                top_k=self.settings.rag_top_k,
                min_score=self.settings.rag_min_score
            )
            
            # Step 3: Extract context
            contexts = []
            context_texts = []
            
            for result in search_results:
                content = result.get("content", "")
                if content:
                    context_texts.append(content)
                    
                    contexts.append(ContextResult(
                        id=result["id"],
                        type=result["metadata"].get("type", "unknown"),
                        title=result["metadata"].get("title", "Untitled"),
                        snippet=content[:300] + "..." if len(content) > 300 else content,
                        score=result["score"]
                    ))
            
            # Step 4: Generate response
            if not context_texts:
                response = (
                    "I don't have enough information in your journal to answer that question. "
                    "Try adding more entries about this topic, or rephrase your question."
                )
            else:
                response = await llm_service.generate_response(
                    message=query,
                    context=context_texts,
                    history=history
                )
            
            logger.info(f"Generated response with {len(contexts)} contexts")
            return response, contexts
            
        except Exception as e:
            logger.error(f"RAG processing failed: {e}")
            raise
    
    async def upsert_document(
        self,
        id: str,
        content: str,
        metadata: dict
    ) -> bool:
        """
        Add or update a document in the vector database.
        
        1. Generate embedding for the content
        2. Upsert into vector database
        """
        try:
            # Generate embedding
            embedding = await embedding_service.generate_embedding(content)
            
            # Upsert into vector DB
            await vector_db_service.upsert(
                id=id,
                vector=embedding,
                metadata=metadata,
                content=content
            )
            
            logger.info(f"Upserted document: {id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to upsert document: {e}")
            raise
    
    async def delete_document(self, id: str) -> bool:
        """Delete a document from the vector database."""
        try:
            await vector_db_service.delete(id)
            logger.info(f"Deleted document: {id}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete document: {e}")
            raise
    
    async def search_similar(
        self,
        query: str,
        top_k: int = 5,
        filter_conditions: Optional[dict] = None
    ) -> list[SearchResult]:
        """Search for documents similar to the query."""
        try:
            # Generate query embedding
            query_embedding = await embedding_service.generate_embedding(query)
            
            # Search
            results = await vector_db_service.search(
                vector=query_embedding,
                top_k=top_k,
                filter_conditions=filter_conditions,
                min_score=self.settings.rag_min_score
            )
            
            # Convert to SearchResult models
            return [
                SearchResult(
                    id=r["id"],
                    score=r["score"],
                    metadata=r["metadata"],
                    content=r.get("content")
                )
                for r in results
            ]
            
        except Exception as e:
            logger.error(f"Search failed: {e}")
            raise


# Singleton instance
rag_service = RAGService()
