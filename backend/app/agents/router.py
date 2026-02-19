"""
Intent Router - Classifies user queries and routes to the right agent(s).

Uses keyword + pattern matching for fast, reliable routing.
Falls back to multi-source if ambiguous.
"""

import re
import logging
from typing import List, Tuple

from app.agents.state import AgentType, QueryIntent

logger = logging.getLogger(__name__)


class IntentRouter:
    """
    Classifies query intent and determines which agents to invoke.
    
    Uses a scoring system:
    - Each data source (email, drive, journal) has keyword patterns
    - Query is scored against each source
    - High confidence → single agent; ambiguous → multi-agent
    """
    
    # Keyword patterns for each source type
    EMAIL_PATTERNS = {
        # Strong indicators (3 points)
        "strong": [
            r'\bemail[s]?\b', r'\binbox\b', r'\bgmail\b', r'\bmailbox\b',
            r'\bmessage[s]?\b', r'\breceived\b', r'\bsent\b', r'\breply\b',
            r'\bfrom\s+\w+.*(?:said|wrote|sent|emailed)\b',
            r'\bunread\b', r'\bthread[s]?\b', r'\bsubject\b',
        ],
        # Medium indicators (2 points)
        "medium": [
            r'\bsender\b', r'\brecipient\b', r'\bcc\b', r'\bbcc\b',
            r'\battach(?:ment|ed)\b', r'\bforward(?:ed)?\b',
            r'\bnewsletter\b', r'\bnotification[s]?\b',
        ],
        # Weak indicators (1 point)
        "weak": [
            r'\bwho\s+(?:said|wrote|contacted|reached)\b',
            r'\blast\s+(?:week|month|day)\b',
            r'\brecent(?:ly)?\b',
        ],
    }
    
    DRIVE_PATTERNS = {
        "strong": [
            r'\bdocument[s]?\b', r'\bfile[s]?\b', r'\bpdf[s]?\b',
            r'\bdrive\b', r'\bgoogle\s+drive\b', r'\bfolder[s]?\b',
            r'\bspreadsheet[s]?\b', r'\bslide[s]?\b', r'\bpresentation[s]?\b',
            r'\bdoc[s]?\b', r'\bword\b', r'\bexcel\b',
        ],
        "medium": [
            r'\bupload(?:ed)?\b', r'\bdownload(?:ed)?\b',
            r'\bshared\s+(?:with|by)\b', r'\bpage\s+\d+\b',
            r'\breport[s]?\b', r'\bcontract[s]?\b', r'\bresume\b',
            r'\bpolicy\b', r'\bagreement\b', r'\bproposal\b',
        ],
        "weak": [
            r'\bsection\b', r'\bchapter\b', r'\btable\b',
            r'\bheading\b', r'\bparagraph\b',
        ],
    }
    
    JOURNAL_PATTERNS = {
        "strong": [
            r'\bjournal\b', r'\bdiary\b', r'\bentry\b', r'\bentries\b',
            r'\bnote[s]?\b', r'\bwrote\b', r'\brecord(?:ed)?\b',
            r'\breflect(?:ion)?\b', r'\bthought[s]?\b',
        ],
        "medium": [
            r'\bfeel(?:ing|s|t)?\b', r'\bmood\b', r'\bgrateful\b',
            r'\bgoal[s]?\b', r'\bhabit[s]?\b', r'\bprogress\b',
            r'\bachiev(?:ed|ement)\b', r'\blearned\b',
        ],
        "weak": [
            r'\byesterday\b', r'\btoday\b', r'\bremember\b',
            r'\bexperience[s]?\b',
        ],
    }
    
    PROFILE_PATTERNS = {
        "strong": [
            r'\bskill[s]?\b', r'\beducation\b', r'\bexperience\b',
            r'\bqualification[s]?\b', r'\bcertificat(?:e|ion)[s]?\b',
            r'\bprofile\b', r'\bresume\b', r'\bcv\b',
            r'\bwork\s+history\b', r'\bbackground\b',
        ],
        "medium": [
            r'\bproficien(?:t|cy)\b', r'\bexpert(?:ise)?\b',
            r'\bknow(?:ledge)?\b', r'\bschool\b', r'\buniversity\b',
            r'\bdegree\b', r'\bjob\b', r'\bcompany\b',
        ],
        "weak": [
            r'\bcan\s+(?:i|you)\b', r'\bam\s+i\b', r'\bmy\b',
        ],
    }
    
    # Summary-related patterns
    SUMMARY_KEYWORDS = [
        'summarize', 'summary', 'overview', 'recap', 'recent', 'latest',
        'what happened', 'catch me up', 'brief', 'highlights', 'digest',
        'tell me about', 'what\'s new', 'update me',
    ]
    
    def classify(self, query: str) -> Tuple[QueryIntent, List[AgentType]]:
        """
        Classify the query intent and return the target agents.
        
        Returns:
            Tuple of (intent, list of agents to invoke)
        """
        query_lower = query.lower().strip()
        
        # Score each source
        email_score = self._score_source(query_lower, self.EMAIL_PATTERNS)
        drive_score = self._score_source(query_lower, self.DRIVE_PATTERNS)
        journal_score = self._score_source(query_lower, self.JOURNAL_PATTERNS)
        profile_score = self._score_source(query_lower, self.PROFILE_PATTERNS)
        
        is_summary = any(kw in query_lower for kw in self.SUMMARY_KEYWORDS)
        
        scores = {
            AgentType.EMAIL: email_score,
            AgentType.DRIVE: drive_score,
            AgentType.JOURNAL: journal_score,
        }
        
        # Add profile score to journal (journal agent handles profiles too)
        scores[AgentType.JOURNAL] += profile_score
        
        max_score = max(scores.values())
        total_score = sum(scores.values())
        
        logger.info(
            f"Intent scores - Email: {email_score}, Drive: {drive_score}, "
            f"Journal: {journal_score}, Profile: {profile_score}, "
            f"Summary: {is_summary}, Max: {max_score}"
        )
        
        # Decision logic
        if max_score == 0:
            # No specific indicators → search all sources
            intent = QueryIntent.GENERAL
            agents = [AgentType.EMAIL, AgentType.DRIVE, AgentType.JOURNAL]
            
        elif max_score >= 3 and max_score > (total_score - max_score) * 2:
            # Strong single-source signal
            top_agent = max(scores, key=scores.get)
            intent = self._get_intent(top_agent, is_summary)
            agents = [top_agent]
            
        elif sum(1 for s in scores.values() if s > 0) > 1:
            # Multiple sources have signals → multi-source
            intent = QueryIntent.MULTI_SOURCE
            agents = [agent for agent, score in scores.items() if score > 0]
            
        else:
            # Single source with moderate confidence
            top_agent = max(scores, key=scores.get)
            intent = self._get_intent(top_agent, is_summary)
            agents = [top_agent]
        
        logger.info(f"Classified intent: {intent}, agents: {[a.value for a in agents]}")
        return intent, agents
    
    def _score_source(self, query: str, patterns: dict) -> int:
        """Score a query against a set of patterns."""
        score = 0
        
        for pattern in patterns.get("strong", []):
            if re.search(pattern, query, re.IGNORECASE):
                score += 3
        
        for pattern in patterns.get("medium", []):
            if re.search(pattern, query, re.IGNORECASE):
                score += 2
        
        for pattern in patterns.get("weak", []):
            if re.search(pattern, query, re.IGNORECASE):
                score += 1
        
        return score
    
    def _get_intent(self, agent: AgentType, is_summary: bool) -> QueryIntent:
        """Map agent + summary flag to specific intent."""
        if agent == AgentType.EMAIL:
            return QueryIntent.EMAIL_SUMMARY if is_summary else QueryIntent.EMAIL_SEARCH
        elif agent == AgentType.DRIVE:
            return QueryIntent.DRIVE_SUMMARY if is_summary else QueryIntent.DRIVE_SEARCH
        elif agent == AgentType.JOURNAL:
            return QueryIntent.JOURNAL_REFLECT if is_summary else QueryIntent.JOURNAL_SEARCH
        return QueryIntent.GENERAL


# Singleton
intent_router = IntentRouter()
