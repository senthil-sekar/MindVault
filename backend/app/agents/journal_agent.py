"""
Journal Agent - Specialized agent for journal and profile queries.

Handles:
- Journal entry search and reflection
- Profile/skills/education queries
- Personal growth and goal tracking
"""

import logging
from typing import Optional, List, Dict

from app.agents.state import AgentType, AgentResult, RetrievedContext
from app.services.embedding import embedding_service
from app.services.vector_db import vector_db_service
from app.config import get_settings

logger = logging.getLogger(__name__)


class JournalAgent:
    """
    Dedicated agent for journal entries and profile data.
    
    Handles personal reflections, goals, skills, education,
    and work experience queries.
    """
    
    AGENT_TYPE = AgentType.JOURNAL
    
    CONTEXT_INSTRUCTIONS = """You are analyzing the user's PERSONAL DATA — journal entries, skills, education, and work experience.
The following are entries from the user's personal journal and profile.
Be warm, supportive, and insightful in your response.
When referencing journal entries, mention the date and context.
When discussing skills or experience, be accurate about proficiency levels."""
    
    # Types that belong to journal/profile
    JOURNAL_TYPES = ["journal_entry", "journal"]
    PROFILE_TYPES = ["skill", "education", "experience", "certification", "profile"]
    
    def __init__(self):
        self.settings = get_settings()
    
    async def execute(
        self,
        query: str,
        is_summary: bool = False,
        history: Optional[List[Dict[str, str]]] = None
    ) -> AgentResult:
        """
        Execute a journal/profile search.

        For reflection/summary requests: uses two-stage retrieval (overview → full entries)
        For specific queries: searches journal entries and profile items
        """
        try:
            if is_summary:
                return await self._handle_summary(query)
            else:
                return await self._handle_search(query)
        except Exception as e:
            logger.error(f"Journal agent error: {e}")
            return AgentResult(
                agent=self.AGENT_TYPE,
                error=str(e)
            )

    async def _handle_summary(self, query: str) -> AgentResult:
        """
        Two-stage journal reflection/summary:

        Stage 1: Fetch a broad set of journal entries for a high-level overview
        Stage 2: Pull full content for the most relevant entries
        """
        logger.info("Journal Agent: Handling reflection/summary request")

        query_embedding = await embedding_service.generate_embedding(query)

        # Stage 1: Get broad set of journal entries
        results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=20,
            min_score=self.settings.rag_min_score,
            keyword_boost=0.2,
            filter_conditions={"type": "journal_entry"}
        )

        logger.info(f"Journal Agent: Found {len(results)} journal entries")

        # Build overview header
        overview_lines = ["=== JOURNAL OVERVIEW ==="]
        for i, entry in enumerate(results[:15], 1):
            meta = entry.get("metadata", {})
            title = meta.get("title", "Untitled")
            date_str = meta.get("created_at", meta.get("date_str", "Unknown date"))
            category = meta.get("category", "")
            category_text = f" [{category}]" if category else ""
            overview_lines.append(f"{i}. [{date_str}] {title}{category_text}")

        overview_text = "\n".join(overview_lines)

        # Stage 2: Full content for top entries
        contexts = []
        for entry in results[:7]:
            content = entry.get("content", "")
            meta = entry.get("metadata", {})
            if not content:
                continue

            title = meta.get("title", "Untitled")
            date_str = meta.get("created_at", meta.get("date_str", ""))
            category = meta.get("category", "")

            full_text = (
                f"--- JOURNAL ENTRY ---\n"
                f"Title: {title}\n"
                f"Date: {date_str}\n"
                f"Category: {category}\n"
                f"Content:\n{content}\n"
                f"--- END ENTRY ---"
            )

            contexts.append(RetrievedContext(
                id=entry["id"],
                content=full_text,
                source_type="journal",
                title=title,
                score=entry["score"],
                metadata=meta,
            ))

        partial = f"{self.CONTEXT_INSTRUCTIONS}\n\n{overview_text}\n\nDETAILED ENTRIES:\n"
        for ctx in contexts:
            partial += f"\n{ctx.content}\n"

        return AgentResult(
            agent=self.AGENT_TYPE,
            contexts=contexts,
            partial_answer=partial,
            confidence=0.9 if contexts else 0.1,
        )

    async def _handle_search(self, query: str) -> AgentResult:
        """Search journal entries and profile items."""
        logger.info(f"Journal Agent: Searching for '{query[:80]}...'")
        
        query_embedding = await embedding_service.generate_embedding(query)
        
        # Search for journal entries
        journal_results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=self.settings.rag_top_k,
            min_score=self.settings.rag_min_score,
            keyword_boost=0.2,
            filter_conditions={"type": "journal_entry"}
        )
        
        # Search for profile items
        profile_results = await vector_db_service.hybrid_search(
            vector=query_embedding,
            query_text=query,
            top_k=self.settings.rag_top_k,
            min_score=self.settings.rag_min_score,
            keyword_boost=0.2,
            filter_conditions={"type": "profile"}
        )
        
        # Combine and sort by score
        all_results = journal_results + profile_results
        all_results.sort(key=lambda x: x["score"], reverse=True)
        
        logger.info(
            f"Journal Agent: Found {len(journal_results)} journal entries, "
            f"{len(profile_results)} profile items"
        )
        
        contexts = []
        for result in all_results[:self.settings.rag_top_k]:
            content = result.get("content", "")
            meta = result.get("metadata", {})
            if not content:
                continue
            
            doc_type = meta.get("type", "unknown")
            title = meta.get("title", "Untitled")
            date_str = meta.get("created_at", meta.get("date_str", ""))
            category = meta.get("category", "")
            
            if doc_type in self.JOURNAL_TYPES:
                full_text = (
                    f"--- JOURNAL ENTRY ---\n"
                    f"Title: {title}\n"
                    f"Date: {date_str}\n"
                    f"Category: {category}\n"
                    f"Content:\n{content}\n"
                    f"--- END ENTRY ---"
                )
                source_type = "journal"
            else:
                proficiency = meta.get("proficiency", "")
                prof_text = f"\nProficiency: {proficiency}/5" if proficiency else ""
                full_text = (
                    f"--- PROFILE: {doc_type.upper()} ---\n"
                    f"Title: {title}"
                    f"{prof_text}\n"
                    f"Details:\n{content}\n"
                    f"--- END PROFILE ---"
                )
                source_type = "profile"
            
            contexts.append(RetrievedContext(
                id=result["id"],
                content=full_text,
                source_type=source_type,
                title=title,
                score=result["score"],
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


# Singleton
journal_agent = JournalAgent()
