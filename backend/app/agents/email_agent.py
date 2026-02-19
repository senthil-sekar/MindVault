"""
Email Agent - Specialized agent for email-related queries.

Handles:
- Email search (by sender, subject, date, content)
- Email summarization (recent, by thread, by sender)
- Email thread context building
"""

import logging
from typing import Optional, List, Dict

from app.agents.state import AgentType, AgentResult, RetrievedContext
from app.services.embedding import embedding_service
from app.services.vector_db import vector_db_service
from app.config import get_settings

logger = logging.getLogger(__name__)


class EmailAgent:
    """
    Dedicated agent for email queries.
    
    Uses hybrid search (vector + keyword) since email queries
    often involve specific names, dates, or subjects that
    pure semantic search misses.
    """
    
    AGENT_TYPE = AgentType.EMAIL
    
    # Email-specific system prompt fragment
    CONTEXT_INSTRUCTIONS = """You are analyzing the user's EMAIL data.
The following are email messages from the user's Gmail inbox.
Each email includes the Subject, Sender, Date, and Body.
Use these details to provide an accurate, specific answer.
Always mention WHO sent the email and WHEN."""
    
    def __init__(self):
        self.settings = get_settings()
    
    async def execute(
        self,
        query: str,
        is_summary: bool = False,
        history: Optional[List[Dict[str, str]]] = None
    ) -> AgentResult:
        """
        Execute an email-specific search and return results.
        
        For summary requests: uses two-stage retrieval (headers → full content)
        For specific queries: uses hybrid search with keyword boosting
        """
        try:
            if is_summary:
                return await self._handle_summary(query)
            else:
                return await self._handle_search(query)
        except Exception as e:
            logger.error(f"Email agent error: {e}")
            return AgentResult(
                agent=self.AGENT_TYPE,
                error=str(e)
            )
    
    async def _handle_summary(self, query: str) -> AgentResult:
        """
        Two-stage email summarization:
        
        Stage 1: Fetch recent email headers for a high-level overview
        Stage 2: Pull full content for the top emails
        """
        logger.info("Email Agent: Handling summary request")
        
        query_embedding = await embedding_service.generate_embedding(query)
        
        # Stage 1: Get broad set of emails
        all_results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=20,
            min_score=self.settings.rag_min_score,
            keyword_boost=0.2,
            filter_conditions={"type": "email"}
        )
        
        # Deduplicate by email_id
        unique_emails = self._deduplicate(all_results)
        logger.info(f"Email Agent: Found {len(unique_emails)} unique emails")
        
        # Build overview header
        overview_lines = ["=== EMAIL OVERVIEW ==="]
        for i, email in enumerate(unique_emails[:15], 1):
            meta = email.get("metadata", {})
            subject = meta.get("subject", "No subject")
            sender = meta.get("sender_name", meta.get("sender", "Unknown"))
            date_str = meta.get("date_str", "Unknown date")
            overview_lines.append(f"{i}. [{date_str}] From: {sender} — {subject}")
        
        overview_text = "\n".join(overview_lines)
        
        # Stage 2: Full content for top emails
        contexts = []
        for email in unique_emails[:7]:
            content = email.get("content", "")
            meta = email.get("metadata", {})
            if not content:
                continue
            
            # Build rich context with headers
            subject = meta.get("subject", "No subject")
            sender = meta.get("sender_name", meta.get("sender", "Unknown"))
            date_str = meta.get("date_str", "Unknown date")
            
            full_text = (
                f"--- EMAIL ---\n"
                f"From: {sender}\n"
                f"Subject: {subject}\n"
                f"Date: {date_str}\n"
                f"Body:\n{content}\n"
                f"--- END EMAIL ---"
            )
            
            contexts.append(RetrievedContext(
                id=email["id"],
                content=full_text,
                source_type="email",
                title=f"{subject} (from {sender})",
                score=email["score"],
                metadata=meta,
            ))
        
        # Build partial answer with overview
        partial = f"{self.CONTEXT_INSTRUCTIONS}\n\n{overview_text}\n\nDETAILED EMAILS:\n"
        for ctx in contexts:
            partial += f"\n{ctx.content}\n"
        
        return AgentResult(
            agent=self.AGENT_TYPE,
            contexts=contexts,
            partial_answer=partial,
            confidence=0.9 if contexts else 0.1,
        )
    
    async def _handle_search(self, query: str) -> AgentResult:
        """
        Handle specific email search queries.
        Uses hybrid search with higher keyword weight for name/date matching.
        """
        logger.info(f"Email Agent: Searching for '{query[:80]}...'")
        
        query_embedding = await embedding_service.generate_embedding(query)
        
        # Use hybrid search with strong keyword boost
        results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=self.settings.rag_top_k * 2,
            min_score=self.settings.rag_min_score,
            keyword_boost=0.35,  # Higher keyword weight for specific queries
            filter_conditions={"type": "email"}
        )
        
        unique = self._deduplicate(results)
        logger.info(f"Email Agent: Found {len(unique)} unique emails")
        
        contexts = []
        for email in unique[:self.settings.rag_top_k]:
            content = email.get("content", "")
            meta = email.get("metadata", {})
            if not content:
                continue
            
            subject = meta.get("subject", "No subject")
            sender = meta.get("sender_name", meta.get("sender", "Unknown"))
            date_str = meta.get("date_str", "Unknown date")
            
            full_text = (
                f"--- EMAIL ---\n"
                f"From: {sender}\n"
                f"Subject: {subject}\n"
                f"Date: {date_str}\n"
                f"Body:\n{content}\n"
                f"--- END EMAIL ---"
            )
            
            contexts.append(RetrievedContext(
                id=email["id"],
                content=full_text,
                source_type="email",
                title=f"{subject} (from {sender})",
                score=email["score"],
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
    
    def _deduplicate(self, results: List[Dict]) -> List[Dict]:
        """Deduplicate by email_id, keep highest scoring chunk per email."""
        seen = {}
        for r in results:
            email_id = r.get("metadata", {}).get("email_id", r["id"])
            if email_id not in seen or r["score"] > seen[email_id]["score"]:
                seen[email_id] = r
        
        deduped = list(seen.values())
        deduped.sort(key=lambda x: x["score"], reverse=True)
        return deduped


# Singleton
email_agent = EmailAgent()
