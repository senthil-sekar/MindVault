"""
Drive Agent - Specialized agent for Google Drive document queries.

Handles:
- Document search (by filename, content, folder)
- Document summarization
- Cross-document analysis
"""

import logging
from typing import Optional, List, Dict

from app.agents.state import AgentType, AgentResult, RetrievedContext
from app.services.embedding import embedding_service
from app.services.vector_db import vector_db_service
from app.config import get_settings

logger = logging.getLogger(__name__)


class DriveAgent:
    """
    Dedicated agent for Google Drive / document queries.
    
    Optimized for longer-form content like PDFs, Word docs, and
    Google Docs. Uses higher top_k since documents are chunked
    and we may need multiple chunks from the same document.
    """
    
    AGENT_TYPE = AgentType.DRIVE
    
    CONTEXT_INSTRUCTIONS = """You are analyzing the user's DOCUMENTS from Google Drive.
The following are excerpts from documents (PDFs, Word docs, Google Docs).
Each excerpt includes the filename, page/section info, and content.
Provide accurate answers based ONLY on the document content.
When referencing information, mention WHICH document it comes from."""
    
    def __init__(self):
        self.settings = get_settings()
    
    async def execute(
        self,
        query: str,
        is_summary: bool = False,
        history: Optional[List[Dict[str, str]]] = None
    ) -> AgentResult:
        """Execute a document-specific search."""
        try:
            if is_summary:
                return await self._handle_summary(query)
            else:
                return await self._handle_search(query)
        except Exception as e:
            logger.error(f"Drive agent error: {e}")
            return AgentResult(
                agent=self.AGENT_TYPE,
                error=str(e)
            )
    
    async def _handle_summary(self, query: str) -> AgentResult:
        """Summarize documents - get overview of all docs, then details."""
        logger.info("Drive Agent: Handling summary request")
        
        query_embedding = await embedding_service.generate_embedding(query)
        
        results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=20,
            min_score=self.settings.rag_min_score,
            keyword_boost=0.25,
            filter_conditions={"type": "document"}
        )
        
        # Group chunks by document
        doc_groups = self._group_by_document(results)
        logger.info(f"Drive Agent: Found {len(doc_groups)} documents")
        
        # Build overview
        overview_lines = ["=== DOCUMENT OVERVIEW ==="]
        for i, (_doc_id, chunks) in enumerate(doc_groups.items(), 1):
            meta = chunks[0].get("metadata", {})
            filename = meta.get("filename", "Unknown")
            source = meta.get("source", "google_drive")
            chunk_count = len(chunks)
            overview_lines.append(f"{i}. {filename} ({chunk_count} relevant sections, source: {source})")
        
        overview_text = "\n".join(overview_lines)
        
        # Get best chunks per document
        contexts = []
        for _doc_id, chunks in list(doc_groups.items())[:5]:
            # Take top 2 chunks per document
            for chunk in chunks[:2]:
                content = chunk.get("content", "")
                meta = chunk.get("metadata", {})
                if not content:
                    continue
                
                filename = meta.get("filename", "Unknown")
                chunk_idx = meta.get("chunk_index", 0)
                total_chunks = meta.get("total_chunks", 1)
                
                full_text = (
                    f"--- DOCUMENT: {filename} (Section {chunk_idx + 1}/{total_chunks}) ---\n"
                    f"{content}\n"
                    f"--- END SECTION ---"
                )
                
                contexts.append(RetrievedContext(
                    id=chunk["id"],
                    content=full_text,
                    source_type="document",
                    title=f"{filename} (section {chunk_idx + 1})",
                    score=chunk["score"],
                    metadata=meta,
                ))
        
        partial = f"{self.CONTEXT_INSTRUCTIONS}\n\n{overview_text}\n\nDOCUMENT CONTENT:\n"
        for ctx in contexts:
            partial += f"\n{ctx.content}\n"
        
        return AgentResult(
            agent=self.AGENT_TYPE,
            contexts=contexts,
            partial_answer=partial,
            confidence=0.9 if contexts else 0.1,
        )
    
    async def _handle_search(self, query: str) -> AgentResult:
        """Search documents for specific information."""
        logger.info(f"Drive Agent: Searching for '{query[:80]}...'")
        
        query_embedding = await embedding_service.generate_embedding(query)
        
        results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=self.settings.rag_top_k * 3,  # More results since docs are chunked
            min_score=self.settings.rag_min_score,
            keyword_boost=0.25,
            filter_conditions={"type": "document"}
        )
        
        # Group by document and pick best chunks
        doc_groups = self._group_by_document(results)
        logger.info(f"Drive Agent: Found {len(doc_groups)} documents")
        
        contexts = []
        for _doc_id, chunks in list(doc_groups.items())[:5]:
            for chunk in chunks[:2]:  # Top 2 chunks per doc
                content = chunk.get("content", "")
                meta = chunk.get("metadata", {})
                if not content:
                    continue
                
                filename = meta.get("filename", "Unknown")
                chunk_idx = meta.get("chunk_index", 0)
                total_chunks = meta.get("total_chunks", 1)
                
                full_text = (
                    f"--- DOCUMENT: {filename} (Section {chunk_idx + 1}/{total_chunks}) ---\n"
                    f"{content}\n"
                    f"--- END SECTION ---"
                )
                
                contexts.append(RetrievedContext(
                    id=chunk["id"],
                    content=full_text,
                    source_type="document",
                    title=f"{filename} (section {chunk_idx + 1})",
                    score=chunk["score"],
                    metadata=meta,
                ))
        
        partial = f"{self.CONTEXT_INSTRUCTIONS}\n\n"
        for ctx in contexts:
            partial += f"\n{ctx.content}\n"
        
        return AgentResult(
            agent=self.AGENT_TYPE,
            contexts=contexts,
            partial_answer=partial,
            confidence=0.8 if contexts else 0.0,
        )
    
    def _group_by_document(self, results: List[Dict]) -> Dict[str, List[Dict]]:
        """Group search results by their parent document."""
        groups: Dict[str, List[Dict]] = {}
        
        for r in results:
            meta = r.get("metadata", {})
            doc_id = meta.get("file_id", meta.get("document_id", r["id"]))
            
            if doc_id not in groups:
                groups[doc_id] = []
            groups[doc_id].append(r)
        
        # Sort each group by score
        for doc_id in groups:
            groups[doc_id].sort(key=lambda x: x["score"], reverse=True)
        
        # Sort groups by best chunk score
        sorted_groups = dict(
            sorted(groups.items(), key=lambda item: item[1][0]["score"], reverse=True)
        )
        
        return sorted_groups


# Singleton
drive_agent = DriveAgent()
