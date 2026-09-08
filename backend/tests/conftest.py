"""Shared fixtures. Qdrant, the embedding model, and Ollama are always mocked."""

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient

from app import main


@pytest.fixture
def mocked_services(monkeypatch):
    """Replace the service singletons `app.main` holds with mocks."""
    embedding = MagicMock()
    embedding.is_ready.return_value = True
    embedding.generate_embedding = AsyncMock(return_value=[0.1] * 384)

    vector_db = MagicMock()
    vector_db.connect.return_value = True
    vector_db.is_connected.return_value = True
    vector_db.get_collection_info = AsyncMock(
        return_value={"name": "mindvault", "points_count": 3, "status": "green"}
    )

    rag = MagicMock()
    rag.upsert_document = AsyncMock(return_value=True)
    rag.upsert_email = AsyncMock(return_value=True)
    rag.delete_document = AsyncMock(return_value=True)
    rag.search_similar = AsyncMock(return_value=[])
    rag.process_query = AsyncMock(return_value=("rag answer", []))

    monkeypatch.setattr(main, "embedding_service", embedding)
    monkeypatch.setattr(main, "vector_db_service", vector_db)
    monkeypatch.setattr(main, "rag_service", rag)
    monkeypatch.setattr(main.llm_service, "initialize", lambda: None)

    return {"embedding": embedding, "vector_db": vector_db, "rag": rag}


@pytest.fixture
def client(mocked_services):
    """TestClient that runs the real lifespan against mocked services."""
    with TestClient(main.app) as test_client:
        yield test_client
