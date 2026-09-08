"""Intent classification in app.agents.router."""

import pytest

from app.agents.router import IntentRouter
from app.agents.state import AgentType, QueryIntent


@pytest.fixture
def router():
    return IntentRouter()


@pytest.mark.parametrize(
    "query,agent",
    [
        ("show me the unread emails in my inbox", AgentType.EMAIL),
        ("find the pdf document in my drive folder", AgentType.DRIVE),
        ("what did I write in my journal entry", AgentType.JOURNAL),
        ("what skills and certifications do I have", AgentType.JOURNAL),
    ],
)
def test_strong_signal_routes_to_single_agent(router, query, agent):
    _, agents = router.classify(query)
    assert agents == [agent]


def test_no_signal_searches_every_source(router):
    intent, agents = router.classify("hello there")
    assert intent == QueryIntent.GENERAL
    assert set(agents) == {AgentType.EMAIL, AgentType.DRIVE, AgentType.JOURNAL}


def test_mixed_signals_go_multi_source(router):
    intent, agents = router.classify("find the email and the document about the contract")
    assert intent == QueryIntent.MULTI_SOURCE
    assert AgentType.EMAIL in agents and AgentType.DRIVE in agents


@pytest.mark.parametrize(
    "query,intent",
    [
        ("summarize my emails from this week", QueryIntent.EMAIL_SUMMARY),
        ("search my inbox for the invoice thread", QueryIntent.EMAIL_SEARCH),
        ("give me an overview of my journal entries", QueryIntent.JOURNAL_REFLECT),
    ],
)
def test_summary_keywords_pick_the_summary_intent(router, query, intent):
    assert router.classify(query)[0] == intent


def test_scoring_weights_strong_over_weak(router):
    strong = router._score_source("my inbox", IntentRouter.EMAIL_PATTERNS)
    weak = router._score_source("recently", IntentRouter.EMAIL_PATTERNS)
    assert strong > weak > 0
