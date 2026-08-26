"""
Qdrant Vector Database Service
"""

import logging
import uuid
from typing import Optional, Any, List, Dict
from qdrant_client import QdrantClient
from qdrant_client.http import models

from app.config import get_settings

logger = logging.getLogger(__name__)


class VectorDBService:
    """Service for interacting with Qdrant vector database."""
    
    def __init__(self):
        self.settings = get_settings()
        self.client: Optional[QdrantClient] = None
        self.collection_name = self.settings.qdrant_collection
    
    def _to_uuid(self, id: str) -> str:
        """Convert string ID to UUID format."""
        try:
            # If already a valid UUID, return it
            uuid.UUID(id)
            return id
        except ValueError:
            # Generate UUID from string hash
            return str(uuid.uuid5(uuid.NAMESPACE_DNS, id))
        
    def connect(self) -> bool:
        """Establish connection to Qdrant."""
        try:
            if self.settings.qdrant_url:
                # Connect to Qdrant Cloud
                self.client = QdrantClient(
                    url=self.settings.qdrant_url,
                    api_key=self.settings.qdrant_api_key,
                )
            else:
                # Connect to local Qdrant
                self.client = QdrantClient(
                    host=self.settings.qdrant_host,
                    port=self.settings.qdrant_port,
                )
            
            # Create collection if it doesn't exist
            self._ensure_collection()
            
            logger.info("Connected to Qdrant successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to Qdrant: {e}")
            return False
    
    def _ensure_collection(self):
        """Create the collection if it doesn't exist."""
        collections = self.client.get_collections().collections
        collection_names = [c.name for c in collections]
        
        if self.collection_name not in collection_names:
            self.client.create_collection(
                collection_name=self.collection_name,
                vectors_config=models.VectorParams(
                    size=self.settings.embedding_dimension,
                    distance=models.Distance.COSINE,
                ),
            )
            logger.info(f"Created collection: {self.collection_name}")
    
    def is_connected(self) -> bool:
        """Check if connected to Qdrant."""
        if not self.client:
            return False
        try:
            self.client.get_collections()
            return True
        except Exception:
            return False
    
    async def upsert(
        self,
        id: str,
        vector: List[float],
        metadata: Dict[str, Any],
        content: Optional[str] = None
    ) -> bool:
        """Upsert a document into the vector database."""
        try:
            payload = {**metadata}
            if content:
                payload["content"] = content
            
            # Convert ID to UUID format
            point_id = self._to_uuid(id)
            
            self.client.upsert(
                collection_name=self.collection_name,
                points=[
                    models.PointStruct(
                        id=point_id,
                        vector=vector,
                        payload=payload,
                    )
                ],
            )
            logger.info(f"Upserted document: {id} (UUID: {point_id})")
            return True
            
        except Exception as e:
            logger.error(f"Failed to upsert document {id}: {e}")
            raise
    
    async def delete(self, id: str) -> bool:
        """Delete a document from the vector database."""
        try:
            # Convert ID to UUID format
            point_id = self._to_uuid(id)
            
            self.client.delete(
                collection_name=self.collection_name,
                points_selector=models.PointIdsList(points=[point_id]),
            )
            logger.info(f"Deleted document: {id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete document {id}: {e}")
            raise
    
    async def search(
        self,
        vector: List[float],
        top_k: int = 5,
        filter_conditions: Optional[Dict] = None,
        min_score: Optional[float] = None
    ) -> List[Dict]:
        """Search for similar documents."""
        try:
            # Build filter if provided
            query_filter = None
            if filter_conditions:
                # Convert filter conditions to Qdrant filter format
                # Example: {"category": "work"} -> Filter with must match
                must_conditions = []
                for key, value in filter_conditions.items():
                    must_conditions.append(
                        models.FieldCondition(
                            key=key,
                            match=models.MatchValue(value=value)
                        )
                    )
                if must_conditions:
                    query_filter = models.Filter(must=must_conditions)
            
            # Perform search
            results = self.client.search(
                collection_name=self.collection_name,
                query_vector=vector,
                limit=top_k,
                query_filter=query_filter,
                score_threshold=min_score,
            )
            
            # Format results
            formatted_results = []
            for result in results:
                formatted_results.append({
                    "id": str(result.id),
                    "score": float(result.score),
                    "metadata": result.payload,
                    "content": result.payload.get("content", "")
                })
            
            return formatted_results
            
        except Exception as e:
            logger.error(f"Search failed: {e}")
            raise
    
    async def hybrid_search(
        self,
        vector: List[float],
        query_text: str,
        top_k: int = 5,
        filter_conditions: Optional[Dict] = None,
        min_score: Optional[float] = None,
        keyword_boost: float = 0.3
    ) -> List[Dict]:
        """
        Hybrid search combining semantic (vector) and keyword search.
        
        This is particularly effective for email search where queries often
        contain specific names, dates, or terms that benefit from exact matching.
        
        Args:
            vector: Query embedding vector
            query_text: Original query text for keyword matching
            top_k: Number of results to return
            filter_conditions: Metadata filters
            min_score: Minimum similarity score
            keyword_boost: Weight for keyword matches (0-1)
            
        Returns:
            Combined and re-ranked results
        """
        try:
            # Step 1: Semantic search
            semantic_results = await self.search(
                vector=vector,
                top_k=top_k * 2,  # Get more results for re-ranking
                filter_conditions=filter_conditions,
                min_score=min_score
            )
            
            # Step 2: Extract keywords from query for matching
            keywords = self._extract_query_keywords(query_text)
            logger.info(f"Hybrid search keywords: {keywords}")
            
            # Step 3: Boost scores based on keyword matches
            for result in semantic_results:
                keyword_score = self._calculate_keyword_score(result, keywords)
                
                # Combine scores: semantic_score * (1 - boost) + keyword_score * boost
                original_score = result["score"]
                boosted_score = (original_score * (1 - keyword_boost)) + (keyword_score * keyword_boost)
                result["score"] = boosted_score
                result["semantic_score"] = original_score
                result["keyword_score"] = keyword_score
            
            # Step 4: Re-rank by combined score
            semantic_results.sort(key=lambda x: x["score"], reverse=True)
            
            # Step 5: Return top_k
            return semantic_results[:top_k]
            
        except Exception as e:
            logger.error(f"Hybrid search failed: {e}")
            raise
    
    def _extract_query_keywords(self, query: str) -> List[str]:
        """Extract keywords from query for matching."""
        import re
        
        # Clean and tokenize
        query = query.lower()
        words = re.findall(r'\b[a-z0-9]+\b', query)
        
        # Remove common stop words
        stop_words = {
            'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
            'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
            'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
            'what', 'when', 'where', 'who', 'how', 'why', 'which', 'this', 'that',
            'my', 'your', 'our', 'their', 'me', 'you', 'we', 'they', 'it', 'its',
            'about', 'any', 'all', 'some', 'can', 'could', 'should', 'tell', 'show', 'find', 'get', 'give', 'list', 'summarize', 'recent',
            'latest', 'last', 'email', 'emails', 'message', 'messages'
        }
        
        keywords = [w for w in words if w not in stop_words and len(w) > 1]
        return keywords
    
    def _calculate_keyword_score(self, result: Dict, keywords: List[str]) -> float:
        """Calculate keyword match score for a result."""
        if not keywords:
            return 0.0
        
        metadata = result.get("metadata", {})
        content = result.get("content", "").lower()
        
        # Fields to search with weights
        search_fields = {
            "subject": 2.0,  # Subject matches are most important
            "sender_name": 1.5,
            "sender_email": 1.5,
            "subject_keywords": 1.0,
        }
        
        total_score = 0.0
        max_possible = len(keywords) * sum(search_fields.values()) + len(keywords)  # +content
        
        for keyword in keywords:
            # Check metadata fields
            for field, weight in search_fields.items():
                field_value = str(metadata.get(field, "")).lower()
                if keyword in field_value:
                    total_score += weight
            
            # Check content
            if keyword in content:
                total_score += 1.0
        
        # Normalize to 0-1
        return min(total_score / max_possible, 1.0) if max_possible > 0 else 0.0
    
    async def search_by_text(
        self,
        query_text: str,
        fields: List[str],
        top_k: int = 5,
        filter_conditions: Optional[Dict] = None
    ) -> List[Dict]:
        """
        Pure keyword/text search without vectors.
        Useful for exact name or date queries.
        """
        try:
            # Build text match conditions
            should_conditions = []
            for field in fields:
                should_conditions.append(
                    models.FieldCondition(
                        key=field,
                        match=models.MatchText(text=query_text)
                    )
                )
            
            # Build filter
            query_filter = models.Filter(
                should=should_conditions,
                min_should=models.MinShould(conditions=should_conditions, min_count=1)
            )
            
            # Add additional filter conditions
            if filter_conditions:
                must_conditions = []
                for key, value in filter_conditions.items():
                    must_conditions.append(
                        models.FieldCondition(
                            key=key,
                            match=models.MatchValue(value=value)
                        )
                    )
                query_filter.must = must_conditions
            
            # Scroll through matching results
            results, _ = self.client.scroll(
                collection_name=self.collection_name,
                scroll_filter=query_filter,
                limit=top_k,
                with_payload=True,
                with_vectors=False
            )
            
            formatted_results = []
            for result in results:
                formatted_results.append({
                    "id": str(result.id),
                    "score": 1.0,  # No vector score for text search
                    "metadata": result.payload,
                    "content": result.payload.get("content", "")
                })
            
            return formatted_results
            
        except Exception as e:
            logger.error(f"Text search failed: {e}")
            raise
    
    async def get_collection_info(self) -> dict:
        """Get information about the collection."""
        try:
            collection_info = self.client.get_collection(self.collection_name)
            return {
                "name": self.collection_name,
                "vector_size": collection_info.config.params.vectors.size,
                "vectors_count": collection_info.vectors_count,
                "points_count": collection_info.points_count,
                "status": collection_info.status
            }
        except Exception as e:
            logger.error(f"Failed to get collection info: {e}")
            raise
    
    async def clear_collection(self) -> bool:
        """Clear all documents from the collection."""
        try:
            self.client.delete_collection(self.collection_name)
            self._ensure_collection()
            logger.info(f"Cleared collection: {self.collection_name}")
            return True
        except Exception as e:
            logger.error(f"Failed to clear collection: {e}")
            raise


# Global instance
vector_db_service = VectorDBService()
