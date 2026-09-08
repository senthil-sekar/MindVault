"""
RAG (Retrieval-Augmented Generation) Service
Orchestrates embedding, search, and LLM for answering questions.

Features:
- Hybrid search (semantic + keyword) for better email retrieval
- Two-stage summarization workflow for email summaries
- Thread-aware context building
- Rich metadata support
"""

import logging
from typing import Optional, Tuple, List, Dict
from datetime import datetime

from app.services.embedding import embedding_service
from app.services.vector_db import vector_db_service
from app.services.llm import llm_service
from app.services.email_processor import email_processor
from app.models import SearchResult, ContextResult
from app.config import get_settings

logger = logging.getLogger(__name__)


class RAGService:
    """Orchestrates RAG pipeline for answering questions."""
    
    # Keywords that indicate a summarization request
    SUMMARY_KEYWORDS = [
        'summarize', 'summary', 'overview', 'recap', 'recent', 'latest',
        'what happened', 'catch me up', 'brief', 'highlights', 'digest'
    ]
    
    def __init__(self):
        self.settings = get_settings()
    
    def _is_summary_request(self, query: str) -> bool:
        """Check if the query is asking for a summary."""
        query_lower = query.lower()
        return any(keyword in query_lower for keyword in self.SUMMARY_KEYWORDS)
    
    async def process_query(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None
    ) -> Tuple[str, List[ContextResult]]:
        """
        Process a user query using RAG with intelligent routing.
        
        Routes to:
        - Summarization workflow for summary requests
        - Hybrid search for specific queries about names/dates
        - Standard search for general queries
        
        Returns:
            Tuple of (response_text, list of contexts used)
        """
        try:
            logger.info(f"Processing query: {query[:100]}...")
            
            # Route based on query type
            if self._is_summary_request(query):
                return await self._handle_summary_request(query, history)
            else:
                return await self._handle_specific_query(query, history)
                
        except Exception as e:
            logger.error(f"RAG processing failed: {e}")
            raise
    
    async def _handle_summary_request(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None
    ) -> Tuple[str, List[ContextResult]]:
        """
        Two-stage summarization workflow:
        
        Stage 1: Retrieve email headers/metadata (fast overview)
        Stage 2: Pull full content for the most relevant threads
        
        This gives the LLM a "map" of emails before diving into details.
        """
        logger.info("Handling summary request with two-stage retrieval")
        
        # Stage 1: Get recent email headers (metadata only)
        query_embedding = await embedding_service.generate_embedding(query)
        
        # Search with higher limit to get overview
        all_results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=20,  # Get more for overview
            min_score=self.settings.rag_min_score,
            keyword_boost=0.2
        )
        
        # Deduplicate by email_id
        seen_emails = {}
        for result in all_results:
            email_id = result.get("metadata", {}).get("email_id", result["id"])
            if email_id not in seen_emails:
                seen_emails[email_id] = result
        
        unique_emails = list(seen_emails.values())
        logger.info(f"Stage 1: Found {len(unique_emails)} unique emails")
        
        # Create email overview for LLM
        email_overview = self._create_email_overview(unique_emails[:15])
        
        # Stage 2: Get full content for top 5 most relevant emails
        top_emails = unique_emails[:5]
        full_contexts = []
        context_texts = []
        
        for email in top_emails:
            content = email.get("content", "")
            if content:
                context_texts.append(content)
                metadata = email.get("metadata", {})
                full_contexts.append(ContextResult(
                    id=email["id"],
                    type=metadata.get("type", "email"),
                    title=metadata.get("subject", "Untitled"),
                    snippet=content[:300] + "..." if len(content) > 300 else content,
                    score=email["score"]
                ))
        
        # Build prompt with overview + details
        enhanced_context = f"""EMAIL OVERVIEW (Recent emails in your inbox):
{email_overview}

DETAILED CONTENT (Most relevant emails):
""" + "\n\n---\n\n".join(context_texts)
        
        # Generate response
        if not context_texts:
            response = "I don't have any emails to summarize. Please sync your emails first."
        else:
            response = await llm_service.generate_response(
                message=query,
                context=[enhanced_context],
                history=history
            )
        
        return response, full_contexts
    
    def _create_email_overview(self, emails: List[Dict]) -> str:
        """Create a structured overview of emails for the LLM."""
        lines = []
        for i, email in enumerate(emails, 1):
            metadata = email.get("metadata", {})
            subject = metadata.get("subject", "No subject")
            sender = metadata.get("sender_name", metadata.get("sender", "Unknown"))
            date_str = metadata.get("date_str", "Unknown date")
            
            # Truncate subject if too long
            if len(subject) > 60:
                subject = subject[:57] + "..."
            
            lines.append(f"{i}. [{date_str}] From: {sender}")
            lines.append(f"   Subject: {subject}")
        
        return "\n".join(lines)
    
    async def _handle_specific_query(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None
    ) -> Tuple[str, List[ContextResult]]:
        """
        Handle specific queries (e.g., "What did John say about the project?")
        Uses hybrid search for better name/date matching.
        """
        logger.info("Handling specific query with hybrid search")
        
        query_embedding = await embedding_service.generate_embedding(query)
        
        # Use hybrid search for better results with names/dates
        search_results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=self.settings.rag_top_k * 2,  # Get more for deduplication
            min_score=self.settings.rag_min_score,
            keyword_boost=0.3  # 30% weight to keyword matching
        )
        
        logger.info(f"Found {len(search_results)} search results")
        
        # Deduplicate by email_id (keep best chunk per email)
        deduplicated = self._deduplicate_results(search_results)
        logger.info(f"After deduplication: {len(deduplicated)} unique emails")
        
        # Extract context
        contexts = []
        context_texts = []
        
        for result in deduplicated[:self.settings.rag_top_k]:
            content = result.get("content", "")
            if content:
                context_texts.append(content)
                metadata = result.get("metadata", {})
                contexts.append(ContextResult(
                    id=result["id"],
                    type=metadata.get("type", "unknown"),
                    title=metadata.get("subject", metadata.get("title", "Untitled")),
                    snippet=content[:300] + "..." if len(content) > 300 else content,
                    score=result["score"]
                ))
        
        # Generate response
        if not context_texts:
            response = (
                "I couldn't find any relevant emails matching your query. "
                "Try rephrasing or ask about a different topic."
            )
        else:
            response = await llm_service.generate_response(
                message=query,
                context=context_texts,
                history=history
            )
        
        return response, contexts
    
    def _deduplicate_results(self, results: List[Dict]) -> List[Dict]:
        """
        Deduplicate search results by email_id, keeping highest scoring chunk.
        """
        seen_emails = {}
        
        for result in results:
            email_id = result.get("metadata", {}).get("email_id", result["id"])
            
            if email_id not in seen_emails:
                seen_emails[email_id] = result
            else:
                if result["score"] > seen_emails[email_id]["score"]:
                    seen_emails[email_id] = result
        
        deduplicated = list(seen_emails.values())
        deduplicated.sort(key=lambda x: x["score"], reverse=True)
        return deduplicated
    
    async def upsert_email(
        self,
        email_id: str,
        raw_content: str,
        subject: str,
        sender: str,
        date: datetime,
        thread_id: Optional[str] = None,
        labels: Optional[List[str]] = None
    ) -> bool:
        """
        Process and upsert an email using the improved email processor.
        
        This method:
        1. Cleans the email (removes signatures, disclaimers, HTML)
        2. Chunks the content with context preservation
        3. Creates rich metadata for hybrid search
        4. Upserts all chunks to vector DB
        """
        try:
            # Process email through the email processor
            processed = email_processor.process_email(
                raw_content=raw_content,
                email_id=email_id,
                subject=subject,
                sender=sender,
                date=date,
                thread_id=thread_id,
                labels=labels
            )
            
            logger.info(
                f"Processed email: {processed.subject[:50]}... "
                f"({len(processed.chunks)} chunks, body length: {len(processed.body_clean)})"
            )
            
            # Upsert each chunk
            for chunk in processed.chunks:
                embedding = await embedding_service.generate_embedding(chunk.content)
                metadata = {**chunk.metadata, "content": chunk.content}
                
                await vector_db_service.upsert(
                    id=chunk.chunk_id,
                    vector=embedding,
                    metadata=metadata,
                    content=chunk.content
                )
            
            logger.info(f"Successfully upserted email: {email_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to upsert email: {e}")
            raise
    
    async def upsert_document(
        self,
        id: str,
        content: str,
        metadata: dict
    ) -> bool:
        """Add or update a document in the vector database (legacy)."""
        try:
            embedding = await embedding_service.generate_embedding(content)
            
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
    
    async def delete_email(self, email_id: str, max_chunks: int = 100) -> bool:
        """Delete all chunks for an email."""
        try:
            for i in range(max_chunks):
                chunk_id = f"{email_id}_{i}"
                try:
                    await vector_db_service.delete(chunk_id)
                except Exception:
                    break
            
            logger.info(f"Deleted email and chunks: {email_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete email: {e}")
            raise
    
    async def search_similar(
        self,
        query: str,
        top_k: int = 5,
        filter_conditions: Optional[Dict] = None
    ) -> List[SearchResult]:
        """Search for documents similar to the query."""
        try:
            query_embedding = await embedding_service.generate_embedding(query)
            
            results = await vector_db_service.hybrid_search(
                vector=query_embedding,
                query_text=query,
                top_k=top_k,
                filter_conditions=filter_conditions,
                min_score=self.settings.rag_min_score
            )
            
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
