"""
Qdrant Vector Database Service
"""

import logging
import uuid
from typing import Optional, Any
from qdrant_client import QdrantClient
from qdrant_client.http import models
from qdrant_client.http.exceptions import UnexpectedResponse

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
        vector: list[float],
        metadata: dict[str, Any],
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
        vector: list[float],
        top_k: int = 5,
        filter_conditions: Optional[dict] = None,
        min_score: Optional[float] = None
    ) -> list[dict]:
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
    
    async def get_collection_info(self) -> dict:
        """Get information about the collection."""
        try:
            collection_info = self.client.get_collection(self.collection_name)
            return {
                "name": collection_info.config.params.vectors.size,
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
