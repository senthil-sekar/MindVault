"""
MindVault Agent System
LangGraph-based multi-agent orchestrator with dedicated agents for
email, drive, journal, and general queries.
"""

from app.agents.orchestrator import agent_orchestrator

__all__ = ["agent_orchestrator"]
