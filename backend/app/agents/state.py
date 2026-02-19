"""
Shared state and types for the agent system.
"""

from typing import Optional, List, Dict, Any
from dataclasses import dataclass, field
from enum import Enum


class AgentType(str, Enum):
    """Types of specialized agents."""
    EMAIL = "email"
    DRIVE = "drive"
    JOURNAL = "journal"
    GENERAL = "general"


class QueryIntent(str, Enum):
    """Classified intent of a user query."""
    EMAIL_SUMMARY = "email_summary"
    EMAIL_SEARCH = "email_search"
    DRIVE_SEARCH = "drive_search"
    DRIVE_SUMMARY = "drive_summary"
    JOURNAL_SEARCH = "journal_search"
    JOURNAL_REFLECT = "journal_reflect"
    PROFILE_QUERY = "profile_query"
    MULTI_SOURCE = "multi_source"
    GENERAL = "general"


@dataclass
class RetrievedContext:
    """A single piece of context retrieved by an agent."""
    id: str
    content: str
    source_type: str  # "email", "drive", "journal", "profile"
    title: str
    score: float
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class AgentResult:
    """Result from a specialized agent."""
    agent: AgentType
    contexts: List[RetrievedContext] = field(default_factory=list)
    partial_answer: str = ""
    confidence: float = 0.0
    error: Optional[str] = None


class OrchestratorState:
    """
    Shared state passed through the LangGraph pipeline.
    
    This is a plain dict-based state that LangGraph uses to track
    the query through routing → agent execution → synthesis.
    """
    pass


# State keys used by the graph
STATE_KEYS = {
    "query": str,                    # User's original query
    "history": list,                 # Chat history
    "intent": str,                   # Classified intent
    "target_agents": list,           # Which agents to invoke
    "agent_results": list,           # Results from each agent
    "final_response": str,           # Synthesized response
    "contexts": list,                # All contexts for citation
}
