"""Unit tests for app.services.rag.RAGService that exercise its real implementation
(as opposed to test_api.py, which mocks rag_service entirely at the API boundary).

Written as sync tests driven via asyncio.run rather than `async def test_...`,
since pytest-asyncio isn't a declared project dependency (see requirements-dev.txt) —
matching the rest of the suite, which drives async code through FastAPI's TestClient.
"""

import asyncio
from unittest.mock import AsyncMock

import pytest

from app.services.rag import RAGService


@pytest.fixture
def rag(monkeypatch):
    """A RAGService with vector_db_service mocked, real delete_document logic."""
    vector_db = AsyncMock()
    monkeypatch.setattr("app.services.rag.vector_db_service", vector_db)
    service = RAGService()
    service._vector_db_mock = vector_db  # stashed for assertions
    return service


def test_delete_document_sweeps_email_chunks(rag):
    """Long emails are chunked by email_processor into {id}_0, {id}_1, ...
    delete_document is the only delete path the API exposes, so it has to
    clean up those chunks too, not just the bare id."""
    calls = []

    async def fake_delete(doc_id):
        calls.append(doc_id)
        if doc_id in ("email-1", "email-1_0", "email-1_1"):
            return True
        raise Exception("not found")  # simulates chunk ids beyond the last real chunk

    rag._vector_db_mock.delete.side_effect = fake_delete

    result = asyncio.run(rag.delete_document("email-1"))

    assert result is True
    assert calls == ["email-1", "email-1_0", "email-1_1", "email-1_2"]


def test_delete_document_handles_non_chunked_document(rag):
    """A journal entry or profile item has no chunk suffixes: the bare-id
    delete succeeds and the very first chunk-suffix probe fails immediately,
    so the sweep stops after one extra call."""
    calls = []

    async def fake_delete(doc_id):
        calls.append(doc_id)
        if doc_id == "journal-1":
            return True
        raise Exception("not found")

    rag._vector_db_mock.delete.side_effect = fake_delete

    result = asyncio.run(rag.delete_document("journal-1"))

    assert result is True
    assert calls == ["journal-1", "journal-1_0"]


def test_delete_document_propagates_error_on_bare_id_failure(rag):
    rag._vector_db_mock.delete.side_effect = Exception("qdrant unreachable")

    with pytest.raises(Exception, match="qdrant unreachable"):
        asyncio.run(rag.delete_document("entry-1"))
