"""
LangGraph Agent Orchestrator
Coordinates multiple specialized agents using a state graph.

Flow:
  User Query → Router → Agent(s) → Synthesizer → Response

The graph:
  1. ROUTE:      Classify intent, pick agents
  2. RETRIEVE:   Run selected agents in parallel (each searches its own data)
  3. SYNTHESIZE: Merge all agent results, generate final LLM response
"""

import logging
from typing import Optional, List, Dict, Tuple, TypedDict

from langgraph.graph import StateGraph, END

from app.agents.state import (
    AgentType, QueryIntent
)
from app.agents.router import intent_router
from app.agents.email_agent import email_agent
from app.agents.drive_agent import drive_agent
from app.agents.journal_agent import journal_agent
from app.services.llm import llm_service
from app.services.rag import rag_service
from app.models import ContextResult

logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────
# LangGraph State Definition
# ──────────────────────────────────────────────

class GraphState(TypedDict):
    """State that flows through the LangGraph pipeline."""
    query: str
    history: Optional[List[Dict[str, str]]]
    intent: str
    target_agents: List[str]
    agent_results: List[dict]
    final_response: str
    contexts: List[dict]


# ──────────────────────────────────────────────
# Graph Node Functions
# ──────────────────────────────────────────────

async def route_node(state: GraphState) -> GraphState:
    """
    Node 1: ROUTE
    Classify the user query and decide which agents to invoke.
    """
    query = state["query"]
    
    intent, agents = intent_router.classify(query)
    
    logger.info(f"🔀 Router → intent={intent.value}, agents={[a.value for a in agents]}")
    
    return {
        **state,
        "intent": intent.value,
        "target_agents": [a.value for a in agents],
    }


async def retrieve_node(state: GraphState) -> GraphState:
    """
    Node 2: RETRIEVE
    Execute all target agents and collect their results.
    """
    query = state["query"]
    history = state.get("history")
    intent = state["intent"]
    target_agents = state["target_agents"]
    
    is_summary = intent in [
        QueryIntent.EMAIL_SUMMARY.value,
        QueryIntent.DRIVE_SUMMARY.value,
        QueryIntent.JOURNAL_REFLECT.value,
    ]
    
    # Map agent names to agent instances
    agent_map = {
        AgentType.EMAIL.value: email_agent,
        AgentType.DRIVE.value: drive_agent,
        AgentType.JOURNAL.value: journal_agent,
    }
    
    results = []
    
    for agent_name in target_agents:
        agent = agent_map.get(agent_name)
        if not agent:
            logger.warning(f"Unknown agent: {agent_name}")
            continue
        
        logger.info(f"🤖 Executing {agent_name} agent...")
        result = await agent.execute(
            query=query,
            is_summary=is_summary,
            history=history,
        )
        
        # Serialize result for state
        results.append({
            "agent": result.agent.value,
            "contexts": [
                {
                    "id": ctx.id,
                    "content": ctx.content,
                    "source_type": ctx.source_type,
                    "title": ctx.title,
                    "score": ctx.score,
                    "metadata": ctx.metadata,
                }
                for ctx in result.contexts
            ],
            "partial_answer": result.partial_answer,
            "confidence": result.confidence,
            "error": result.error,
        })
        
        logger.info(
            f"  → {agent_name}: {len(result.contexts)} contexts, "
            f"confidence={result.confidence:.2f}"
        )
    
    return {
        **state,
        "agent_results": results,
    }


async def synthesize_node(state: GraphState) -> GraphState:
    """
    Node 3: SYNTHESIZE
    Merge results from all agents and generate the final response.
    
    This is the key node - it takes the structured context from each
    agent and builds a unified prompt for the LLM.
    """
    query = state["query"]
    history = state.get("history")
    agent_results = state["agent_results"]
    
    # Collect all contexts and partial answers
    all_contexts = []
    all_partial_answers = []
    source_labels = []
    
    for result in agent_results:
        if result.get("error"):
            logger.warning(f"Agent {result['agent']} had error: {result['error']}")
            continue
        
        if result.get("partial_answer"):
            all_partial_answers.append(result["partial_answer"])
        
        for ctx in result.get("contexts", []):
            all_contexts.append(ctx)
        
        if result.get("contexts"):
            source_labels.append(result["agent"])
    
    # Sort all contexts by score
    all_contexts.sort(key=lambda x: x["score"], reverse=True)
    
    # Build the merged context for the LLM
    if not all_contexts:
        final_response = (
            "I searched through your emails, documents, and journal entries "
            "but couldn't find information relevant to your question. "
            "Try rephrasing your query, or make sure your data is synced."
        )
        return {
            **state,
            "final_response": final_response,
            "contexts": [],
        }
    
    # Build source-aware prompt
    sources_used = ", ".join(set(source_labels))
    
    merged_context = f"""=== DATA FROM: {sources_used.upper()} ===

"""
    for pa in all_partial_answers:
        merged_context += pa + "\n\n"
    
    # Generate final response via LLM
    context_texts = [merged_context]
    
    logger.info(
        f"📝 Synthesizing from {len(all_contexts)} contexts "
        f"(sources: {sources_used}), prompt length: {len(merged_context)}"
    )
    
    final_response = await llm_service.generate_response(
        message=query,
        context=context_texts,
        history=history,
    )
    
    # Build context results for the iOS app
    context_results = [
        {
            "id": ctx["id"],
            "type": ctx["source_type"],
            "title": ctx["title"],
            "snippet": ctx["content"][:300] + "..." if len(ctx["content"]) > 300 else ctx["content"],
            "score": ctx["score"],
        }
        for ctx in all_contexts[:10]  # Top 10 for citations
    ]
    
    return {
        **state,
        "final_response": final_response,
        "contexts": context_results,
    }


# ──────────────────────────────────────────────
# Build the LangGraph
# ──────────────────────────────────────────────

def build_graph() -> StateGraph:
    """Build the LangGraph agent orchestrator."""
    
    graph = StateGraph(GraphState)
    
    # Add nodes
    graph.add_node("route", route_node)
    graph.add_node("retrieve", retrieve_node)
    graph.add_node("synthesize", synthesize_node)
    
    # Define edges (linear pipeline)
    graph.set_entry_point("route")
    graph.add_edge("route", "retrieve")
    graph.add_edge("retrieve", "synthesize")
    graph.add_edge("synthesize", END)
    
    return graph.compile()


# ──────────────────────────────────────────────
# Orchestrator Class
# ──────────────────────────────────────────────

class AgentOrchestrator:
    """
    Main entry point for the multi-agent system.
    
    Wraps the LangGraph pipeline and provides a simple interface
    for the FastAPI endpoints.
    """
    
    def __init__(self):
        self.graph = build_graph()
        logger.info("✅ Agent Orchestrator initialized with LangGraph")
    
    async def process_query(
        self,
        query: str,
        history: Optional[List[Dict[str, str]]] = None
    ) -> Tuple[str, List[ContextResult]]:
        """
        Process a user query through the agent pipeline.
        
        Returns:
            Tuple of (response_text, list of ContextResult for citations)
        """
        logger.info(f"{'='*60}")
        logger.info(f"🧠 Orchestrator processing: '{query[:100]}...'")
        logger.info(f"{'='*60}")
        
        # Build initial state
        initial_state: GraphState = {
            "query": query,
            "history": history,
            "intent": "",
            "target_agents": [],
            "agent_results": [],
            "final_response": "",
            "contexts": [],
        }
        
        # Run the graph
        final_state = await self.graph.ainvoke(initial_state)
        
        # Extract results
        response = final_state["final_response"]
        raw_contexts = final_state.get("contexts", [])
        
        # Convert to ContextResult models
        contexts = [
            ContextResult(
                id=ctx["id"],
                type=ctx["type"],
                title=ctx["title"],
                snippet=ctx["snippet"],
                score=ctx["score"],
            )
            for ctx in raw_contexts
        ]
        
        logger.info(
            f"✅ Orchestrator done: {len(contexts)} contexts, "
            f"response length: {len(response)}"
        )
        
        return response, contexts
    
    # ──────────────────────────────────────────────
    # Pass-through methods for data operations
    # (These don't need the graph, just use rag_service)
    # ──────────────────────────────────────────────
    
    async def upsert_document(self, id: str, content: str, metadata: dict) -> bool:
        return await rag_service.upsert_document(id, content, metadata)
    
    async def upsert_email(self, **kwargs) -> bool:
        return await rag_service.upsert_email(**kwargs)
    
    async def delete_document(self, id: str) -> bool:
        return await rag_service.delete_document(id)
    
    async def delete_email(self, email_id: str) -> bool:
        return await rag_service.delete_email(email_id)
    
    async def search_similar(self, query: str, top_k: int = 5, filter_conditions=None):
        return await rag_service.search_similar(query, top_k, filter_conditions)


# Singleton
agent_orchestrator = AgentOrchestrator()
