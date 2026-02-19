"""
Email Processing Service for RAG
Handles data cleaning, chunking, and preparation for vector storage.
"""

import re
import logging
from typing import Optional, List, Dict, Any, Tuple
from datetime import datetime
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class ProcessedEmail:
    """Cleaned and structured email data."""
    id: str
    subject: str
    sender: str
    sender_name: str
    sender_email: str
    date: datetime
    date_str: str
    body_clean: str
    thread_id: Optional[str]
    is_reply: bool
    is_forward: bool
    labels: List[str]
    chunks: List['EmailChunk']


@dataclass
class EmailChunk:
    """A chunk of email content with metadata for RAG."""
    chunk_id: str
    content: str
    metadata: Dict[str, Any]
    chunk_index: int
    total_chunks: int


class EmailProcessor:
    """
    Processes raw emails for optimal RAG retrieval.
    
    Key improvements:
    1. Clean HTML and extract structured fields
    2. Remove signatures, disclaimers, forwarded headers
    3. Thread-aware chunking with context preservation
    4. Rich metadata for hybrid search
    """
    
    # Patterns to identify and remove noise
    SIGNATURE_PATTERNS = [
        # Common signature starters
        r'^[\-_]{2,}.*$',  # -- or __
        r'^Sent from my (?:iPhone|iPad|Android|Galaxy|Pixel).*$',
        r'^Get Outlook for (?:iOS|Android).*$',
        r'^Sent via .*$',
        r'^Best regards?,?.*$',
        r'^Kind regards?,?.*$',
        r'^Thanks?,?.*$',
        r'^Thank you,?.*$',
        r'^Sincerely,?.*$',
        r'^Regards,?.*$',
        r'^Cheers,?.*$',
        r'^Best,?.*$',
        r'^Warm regards,?.*$',
    ]
    
    DISCLAIMER_PATTERNS = [
        r'(?:CONFIDENTIAL|PRIVILEGED|DISCLAIMER).*(?:\n.*){0,10}',
        r'This (?:email|message|communication) (?:and any attachments )?(?:is|are) (?:intended )?(?:solely )?for.*',
        r'If you (?:have )?received this (?:email|message) in error.*',
        r'(?:Please )?do not (?:print|forward|distribute) this (?:email|message).*',
        r'This message contains confidential information.*',
        r'(?:Unsubscribe|Click here to unsubscribe).*',
        r'(?:To )?stop receiving these (?:emails|messages).*',
        r'View this email in your browser.*',
        r'Add .* to your address book.*',
        r'(?:Privacy Policy|Terms of Service|Terms & Conditions).*',
    ]
    
    FORWARDED_PATTERNS = [
        r'^[\-]{3,}\s*(?:Forwarded|Original)\s+(?:message|Message)[\-]{3,}.*$',
        r'^From:.*\nSent:.*\nTo:.*\nSubject:.*$',
        r'^On .* wrote:$',
        r'^> .*$',  # Quoted text
    ]
    
    LEGAL_FOOTER_PATTERNS = [
        r'©\s*\d{4}.*(?:All rights reserved|Inc\.|LLC|Corp).*',
        r'(?:Securities|investments) offered through.*',
        r'Member (?:FINRA|SIPC|FDIC).*',
        r'(?:NMLS|License) (?:#|ID:? )?\d+.*',
    ]
    
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
    
    def process_email(
        self,
        raw_content: str,
        email_id: str,
        subject: str,
        sender: str,
        date: datetime,
        thread_id: Optional[str] = None,
        labels: Optional[List[str]] = None
    ) -> ProcessedEmail:
        """
        Process a raw email into clean, chunked format for RAG.
        
        Args:
            raw_content: The raw email body (may contain HTML)
            email_id: Unique identifier
            subject: Email subject line
            sender: Full sender string (e.g., "John Doe <john@example.com>")
            date: Email datetime
            thread_id: Gmail thread ID for grouping
            labels: Gmail labels
            
        Returns:
            ProcessedEmail with cleaned content and chunks
        """
        # Extract sender name and email
        sender_name, sender_email = self._parse_sender(sender)
        
        # Clean the body content
        body_clean = self._clean_email_body(raw_content)
        
        # Detect email type
        is_reply = self._is_reply(subject)
        is_forward = self._is_forward(subject)
        
        # Format date for search
        date_str = date.strftime("%Y-%m-%d %H:%M")
        
        # Create chunks with context
        chunks = self._create_chunks(
            email_id=email_id,
            subject=subject,
            sender_name=sender_name,
            sender_email=sender_email,
            date=date,
            date_str=date_str,
            body=body_clean,
            thread_id=thread_id,
            is_reply=is_reply,
            is_forward=is_forward,
            labels=labels or []
        )
        
        return ProcessedEmail(
            id=email_id,
            subject=subject,
            sender=sender,
            sender_name=sender_name,
            sender_email=sender_email,
            date=date,
            date_str=date_str,
            body_clean=body_clean,
            thread_id=thread_id,
            is_reply=is_reply,
            is_forward=is_forward,
            labels=labels or [],
            chunks=chunks
        )
    
    def _parse_sender(self, sender: str) -> Tuple[str, str]:
        """Extract name and email from sender string."""
        # Pattern: "Name <email@example.com>" or just "email@example.com"
        match = re.match(r'^(.+?)\s*<([^>]+)>$', sender.strip())
        if match:
            name = match.group(1).strip().strip('"\'')
            email = match.group(2).strip()
            return name, email
        
        # Just email address
        email_match = re.match(r'^([^\s@]+@[^\s@]+\.[^\s@]+)$', sender.strip())
        if email_match:
            email = email_match.group(1)
            name = email.split('@')[0]
            return name, email
        
        return sender, sender
    
    def _clean_email_body(self, raw_content: str) -> str:
        """
        Clean email body by removing HTML, signatures, disclaimers, etc.
        """
        text = raw_content
        
        # Step 1: Strip HTML if present
        text = self._strip_html(text)
        
        # Step 2: Remove forwarded message headers and quoted text
        text = self._remove_forwarded_content(text)
        
        # Step 3: Remove signatures
        text = self._remove_signatures(text)
        
        # Step 4: Remove disclaimers and legal footers
        text = self._remove_disclaimers(text)
        
        # Step 5: Clean up whitespace
        text = self._normalize_whitespace(text)
        
        return text
    
    def _strip_html(self, html: str) -> str:
        """Remove HTML tags and decode entities."""
        # Remove script and style elements entirely
        text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL | re.IGNORECASE)
        
        # Remove HTML comments
        text = re.sub(r'<!--.*?-->', '', text, flags=re.DOTALL)
        
        # Convert common block elements to newlines
        text = re.sub(r'<br\s*/?>', '\n', text, flags=re.IGNORECASE)
        text = re.sub(r'</?(?:p|div|tr|li|h[1-6])[^>]*>', '\n', text, flags=re.IGNORECASE)
        text = re.sub(r'<td[^>]*>', ' ', text, flags=re.IGNORECASE)
        
        # Remove all remaining HTML tags
        text = re.sub(r'<[^>]+>', '', text)
        
        # Decode HTML entities
        html_entities = {
            '&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>',
            '&quot;': '"', '&#39;': "'", '&apos;': "'",
            '&ndash;': '–', '&mdash;': '—', '&bull;': '•',
            '&copy;': '©', '&reg;': '®', '&trade;': '™',
            '&hellip;': '...', '&lsquo;': ''', '&rsquo;': ''',
            '&ldquo;': '"', '&rdquo;': '"',
        }
        for entity, char in html_entities.items():
            text = text.replace(entity, char)
        
        # Decode numeric entities
        text = re.sub(r'&#(\d+);', lambda m: chr(int(m.group(1))), text)
        text = re.sub(r'&#x([0-9a-fA-F]+);', lambda m: chr(int(m.group(1), 16)), text)
        
        return text
    
    def _remove_forwarded_content(self, text: str) -> str:
        """Remove forwarded message headers and excessive quoting."""
        lines = text.split('\n')
        clean_lines = []
        skip_mode = False
        quote_count = 0
        
        for line in lines:
            stripped = line.strip()
            
            # Detect forwarded message header
            if re.match(r'^[\-]{3,}\s*(?:Forwarded|Original)\s+(?:message|Message)', stripped, re.IGNORECASE):
                skip_mode = True
                continue
            
            # Detect "On ... wrote:" pattern
            if re.match(r'^On .+ wrote:$', stripped):
                skip_mode = True
                continue
            
            # Skip quoted lines (but allow some for context)
            if stripped.startswith('>'):
                quote_count += 1
                if quote_count > 3:  # Keep at most 3 quoted lines
                    continue
            else:
                quote_count = 0
                skip_mode = False
            
            if not skip_mode:
                clean_lines.append(line)
        
        return '\n'.join(clean_lines)
    
    def _remove_signatures(self, text: str) -> str:
        """Remove email signatures."""
        lines = text.split('\n')
        
        # Find signature start
        sig_start = len(lines)
        for i, line in enumerate(lines):
            stripped = line.strip()
            for pattern in self.SIGNATURE_PATTERNS:
                if re.match(pattern, stripped, re.IGNORECASE):
                    sig_start = i
                    break
            if sig_start != len(lines):
                break
        
        # Keep content before signature
        return '\n'.join(lines[:sig_start])
    
    def _remove_disclaimers(self, text: str) -> str:
        """Remove legal disclaimers and footers."""
        for pattern in self.DISCLAIMER_PATTERNS + self.LEGAL_FOOTER_PATTERNS:
            text = re.sub(pattern, '', text, flags=re.IGNORECASE | re.MULTILINE)
        return text
    
    def _normalize_whitespace(self, text: str) -> str:
        """Clean up excessive whitespace while preserving paragraph structure."""
        # Replace multiple newlines with double newline
        text = re.sub(r'\n{3,}', '\n\n', text)
        
        # Replace multiple spaces with single space
        text = re.sub(r'[^\S\n]+', ' ', text)
        
        # Strip whitespace from each line
        lines = [line.strip() for line in text.split('\n')]
        
        # Remove empty lines at start and end
        while lines and not lines[0]:
            lines.pop(0)
        while lines and not lines[-1]:
            lines.pop()
        
        return '\n'.join(lines)
    
    def _is_reply(self, subject: str) -> bool:
        """Check if email is a reply."""
        return bool(re.match(r'^(?:Re|RE|re):\s*', subject))
    
    def _is_forward(self, subject: str) -> bool:
        """Check if email is forwarded."""
        return bool(re.match(r'^(?:Fwd|FWD|fwd|Fw|FW):\s*', subject))
    
    def _create_chunks(
        self,
        email_id: str,
        subject: str,
        sender_name: str,
        sender_email: str,
        date: datetime,
        date_str: str,
        body: str,
        thread_id: Optional[str],
        is_reply: bool,
        is_forward: bool,
        labels: List[str]
    ) -> List[EmailChunk]:
        """
        Create chunks with rich metadata for hybrid search.
        
        Each chunk includes:
        - Context header (subject, sender, date)
        - Body content
        - Rich metadata for filtering and keyword search
        """
        chunks = []
        
        # If body is short, create single chunk
        if len(body) <= self.chunk_size:
            chunk_content = self._format_chunk_content(
                subject=subject,
                sender_name=sender_name,
                date_str=date_str,
                body=body,
                chunk_index=0,
                total_chunks=1
            )
            
            chunks.append(EmailChunk(
                chunk_id=f"{email_id}_0",
                content=chunk_content,
                metadata=self._create_chunk_metadata(
                    email_id=email_id,
                    subject=subject,
                    sender_name=sender_name,
                    sender_email=sender_email,
                    date=date,
                    date_str=date_str,
                    thread_id=thread_id,
                    is_reply=is_reply,
                    is_forward=is_forward,
                    labels=labels,
                    chunk_index=0,
                    total_chunks=1
                ),
                chunk_index=0,
                total_chunks=1
            ))
            return chunks
        
        # Split into chunks with overlap
        body_chunks = self._split_text(body)
        total_chunks = len(body_chunks)
        
        for i, body_chunk in enumerate(body_chunks):
            chunk_content = self._format_chunk_content(
                subject=subject,
                sender_name=sender_name,
                date_str=date_str,
                body=body_chunk,
                chunk_index=i,
                total_chunks=total_chunks
            )
            
            chunks.append(EmailChunk(
                chunk_id=f"{email_id}_{i}",
                content=chunk_content,
                metadata=self._create_chunk_metadata(
                    email_id=email_id,
                    subject=subject,
                    sender_name=sender_name,
                    sender_email=sender_email,
                    date=date,
                    date_str=date_str,
                    thread_id=thread_id,
                    is_reply=is_reply,
                    is_forward=is_forward,
                    labels=labels,
                    chunk_index=i,
                    total_chunks=total_chunks
                ),
                chunk_index=i,
                total_chunks=total_chunks
            ))
        
        return chunks
    
    def _format_chunk_content(
        self,
        subject: str,
        sender_name: str,
        date_str: str,
        body: str,
        chunk_index: int,
        total_chunks: int
    ) -> str:
        """
        Format chunk content with context header.
        This helps the embedding model understand the context.
        """
        header = f"Email from {sender_name} on {date_str}\nSubject: {subject}"
        
        if total_chunks > 1:
            header += f"\n[Part {chunk_index + 1} of {total_chunks}]"
        
        return f"{header}\n\n{body}"
    
    def _create_chunk_metadata(
        self,
        email_id: str,
        subject: str,
        sender_name: str,
        sender_email: str,
        date: datetime,
        date_str: str,
        thread_id: Optional[str],
        is_reply: bool,
        is_forward: bool,
        labels: List[str],
        chunk_index: int,
        total_chunks: int
    ) -> Dict[str, Any]:
        """
        Create rich metadata for hybrid search.
        
        Includes:
        - Structured fields for filtering (type, labels)
        - Text fields for keyword search (subject, sender)
        - Date fields for range queries
        """
        # Extract keywords from subject for better search
        subject_keywords = self._extract_keywords(subject)
        
        return {
            # Type identifier
            "type": "email",
            
            # Structured fields
            "email_id": email_id,
            "thread_id": thread_id or "",
            "chunk_index": chunk_index,
            "total_chunks": total_chunks,
            
            # Searchable text fields (for keyword/hybrid search)
            "subject": subject,
            "subject_keywords": subject_keywords,
            "sender_name": sender_name,
            "sender_email": sender_email,
            "sender": f"{sender_name} <{sender_email}>",
            
            # Date fields
            "date": date.isoformat(),
            "date_str": date_str,
            "year": date.year,
            "month": date.month,
            "day": date.day,
            
            # Classification
            "is_reply": is_reply,
            "is_forward": is_forward,
            "labels": labels,
            
            # For display
            "title": subject,
        }
    
    def _split_text(self, text: str) -> List[str]:
        """Split text into overlapping chunks, respecting sentence boundaries."""
        # Try to split at sentence boundaries
        sentences = re.split(r'(?<=[.!?])\s+', text)
        
        chunks = []
        current_chunk = []
        current_length = 0
        
        for sentence in sentences:
            sentence_length = len(sentence)
            
            if current_length + sentence_length > self.chunk_size and current_chunk:
                # Save current chunk
                chunks.append(' '.join(current_chunk))
                
                # Start new chunk with overlap
                overlap_text = ' '.join(current_chunk)
                overlap_start = max(0, len(overlap_text) - self.chunk_overlap)
                overlap_content = overlap_text[overlap_start:]
                
                current_chunk = [overlap_content, sentence] if overlap_content else [sentence]
                current_length = len(overlap_content) + sentence_length
            else:
                current_chunk.append(sentence)
                current_length += sentence_length + 1  # +1 for space
        
        if current_chunk:
            chunks.append(' '.join(current_chunk))
        
        return chunks
    
    def _extract_keywords(self, text: str) -> str:
        """Extract important keywords from text for keyword search."""
        # Remove common email prefixes
        text = re.sub(r'^(?:Re|RE|Fwd|FWD|Fw|FW):\s*', '', text)
        
        # Remove special characters but keep alphanumeric and spaces
        text = re.sub(r'[^\w\s]', ' ', text)
        
        # Convert to lowercase and split
        words = text.lower().split()
        
        # Remove common stop words
        stop_words = {
            'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
            'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
            'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
            'could', 'should', 'may', 'might', 'must', 'can', 'this', 'that',
            'these', 'those', 'it', 'its', 'your', 'my', 'our', 'their', 'we',
            'you', 'i', 'me', 'him', 'her', 'them', 'us'
        }
        
        keywords = [w for w in words if w not in stop_words and len(w) > 2]
        
        return ' '.join(keywords[:10])  # Top 10 keywords


# Singleton instance
email_processor = EmailProcessor()
