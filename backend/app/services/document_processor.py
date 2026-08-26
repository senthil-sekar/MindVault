"""
Document Processing Service
Handles PDF, DOCX, and text document extraction and chunking for RAG
"""

import io
import logging
import re
from typing import List, Dict, Any, Optional
from datetime import datetime
import hashlib

logger = logging.getLogger(__name__)

# PDF processing
try:
    import PyPDF2
    HAS_PYPDF2 = True
except ImportError:
    HAS_PYPDF2 = False

try:
    import pdfplumber
    HAS_PDFPLUMBER = True
except ImportError:
    HAS_PDFPLUMBER = False

# DOCX processing
try:
    from docx import Document as DocxDocument
    HAS_DOCX = True
except ImportError:
    HAS_DOCX = False


class DocumentProcessor:
    """Process various document types for RAG indexing"""
    
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
    
    def process_document(
        self,
        content: bytes,
        filename: str,
        mime_type: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> List[Dict[str, Any]]:
        """
        Process a document and return chunks ready for vector DB indexing
        
        Args:
            content: Raw document bytes
            filename: Original filename
            mime_type: MIME type of the document
            metadata: Additional metadata to attach
            
        Returns:
            List of chunk dictionaries with id, content, and metadata
        """
        # Extract text based on type
        if mime_type == "application/pdf":
            text = self._extract_pdf_text(content)
        elif mime_type in [
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/msword"
        ]:
            text = self._extract_docx_text(content)
        elif mime_type.startswith("text/"):
            text = content.decode("utf-8", errors="ignore")
        else:
            raise ValueError(f"Unsupported document type: {mime_type}")
        
        # Clean the text
        text = self._clean_text(text)
        
        if not text.strip():
            return []
        
        # Create chunks
        chunks = self._create_chunks(text, filename)
        
        # Generate document ID from content hash
        doc_hash = hashlib.md5(content).hexdigest()[:12]
        
        # Build chunk documents
        result = []
        for i, chunk in enumerate(chunks):
            chunk_id = f"doc_{doc_hash}_{i}"
            
            chunk_metadata = {
                "type": "document",
                "filename": filename,
                "mime_type": mime_type,
                "chunk_index": i,
                "total_chunks": len(chunks),
                "source": "google_drive",
                "indexed_at": datetime.utcnow().isoformat(),
            }
            
            # Add any extra metadata
            if metadata:
                chunk_metadata.update(metadata)
            
            result.append({
                "id": chunk_id,
                "content": chunk,
                "metadata": chunk_metadata,
            })
        
        return result
    
    def _extract_pdf_text(self, content: bytes) -> str:
        """Extract text from PDF using available library"""
        text_parts = []
        
        # Try pdfplumber first (better quality)
        if HAS_PDFPLUMBER:
            try:
                with pdfplumber.open(io.BytesIO(content)) as pdf:
                    for page in pdf.pages:
                        page_text = page.extract_text()
                        if page_text:
                            text_parts.append(page_text)
                if text_parts:
                    return "\n\n".join(text_parts)
            except Exception as e:
                logger.warning(f"pdfplumber failed: {e}")
        
        # Fallback to PyPDF2
        if HAS_PYPDF2:
            try:
                reader = PyPDF2.PdfReader(io.BytesIO(content))
                for page in reader.pages:
                    page_text = page.extract_text()
                    if page_text:
                        text_parts.append(page_text)
                return "\n\n".join(text_parts)
            except Exception as e:
                logger.warning(f"PyPDF2 failed: {e}")
        
        raise RuntimeError("No PDF library available. Install pdfplumber or PyPDF2.")
    
    def _extract_docx_text(self, content: bytes) -> str:
        """Extract text from DOCX"""
        if not HAS_DOCX:
            raise RuntimeError("python-docx not installed. Run: pip install python-docx")
        
        doc = DocxDocument(io.BytesIO(content))
        paragraphs = []
        
        for para in doc.paragraphs:
            text = para.text.strip()
            if text:
                paragraphs.append(text)
        
        # Also extract from tables
        for table in doc.tables:
            for row in table.rows:
                row_text = " | ".join(cell.text.strip() for cell in row.cells if cell.text.strip())
                if row_text:
                    paragraphs.append(row_text)
        
        return "\n\n".join(paragraphs)
    
    def _clean_text(self, text: str) -> str:
        """Clean extracted text"""
        # Remove excessive whitespace
        text = re.sub(r'\s+', ' ', text)
        
        # Remove common artifacts
        text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '', text)
        
        # Fix common OCR issues
        text = text.replace('ﬁ', 'fi').replace('ﬂ', 'fl')
        
        # Normalize line breaks
        text = re.sub(r'\n{3,}', '\n\n', text)
        
        return text.strip()
    
    def _create_chunks(self, text: str, filename: str) -> List[str]:
        """Split text into overlapping chunks with context headers"""
        if len(text) <= self.chunk_size:
            return [f"Document: {filename}\n\n{text}"]
        
        chunks = []
        sentences = self._split_sentences(text)
        
        current_chunk = []
        current_length = 0
        
        for sentence in sentences:
            sentence_length = len(sentence)
            
            if current_length + sentence_length > self.chunk_size and current_chunk:
                # Save current chunk
                chunk_text = " ".join(current_chunk)
                header = f"Document: {filename}\n[Chunk {len(chunks) + 1}]\n\n"
                chunks.append(header + chunk_text)
                
                # Start new chunk with overlap
                overlap_text = " ".join(current_chunk[-3:])  # Keep last 3 sentences
                current_chunk = [overlap_text] if overlap_text else []
                current_length = len(overlap_text)
            
            current_chunk.append(sentence)
            current_length += sentence_length
        
        # Don't forget the last chunk
        if current_chunk:
            chunk_text = " ".join(current_chunk)
            header = f"Document: {filename}\n[Chunk {len(chunks) + 1}]\n\n"
            chunks.append(header + chunk_text)
        
        return chunks
    
    def _split_sentences(self, text: str) -> List[str]:
        """Split text into sentences"""
        # Simple sentence splitter
        sentences = re.split(r'(?<=[.!?])\s+', text)
        return [s.strip() for s in sentences if s.strip()]


# Singleton instance
document_processor = DocumentProcessor()
