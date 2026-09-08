"""Endpoint tests for app.main. Every external dependency is mocked (see conftest)."""

import base64
from datetime import datetime
from unittest.mock import AsyncMock

from app import main


def test_root(client):
    body = client.get("/").json()
    assert body["service"] == "MindVault API"


def test_health_reports_dependency_state(client, mocked_services):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["vector_db_status"] == "connected"
    assert body["embeddings_ready"] is True

    mocked_services["vector_db"].is_connected.return_value = False
    mocked_services["embedding"].is_ready.return_value = False
    body = client.get("/health").json()
    assert body["vector_db_status"] == "disconnected"
    assert body["embeddings_ready"] is False


def test_embed(client, mocked_services):
    response = client.post("/api/embed", json={"text": "hello"})
    assert response.status_code == 200
    assert len(response.json()["embedding"]) == 384
    mocked_services["embedding"].generate_embedding.assert_awaited_once_with("hello")


def test_embed_rejects_empty_text(client):
    assert client.post("/api/embed", json={"text": ""}).status_code == 422


def test_embed_surfaces_service_failure(client, mocked_services):
    mocked_services["embedding"].generate_embedding.side_effect = RuntimeError("model gone")
    response = client.post("/api/embed", json={"text": "hello"})
    assert response.status_code == 500
    assert "model gone" in response.json()["detail"]


def test_upsert(client, mocked_services):
    response = client.post(
        "/api/upsert",
        json={"id": "entry-1", "content": "Shipped the RAG pipeline", "metadata": {"type": "journal_entry"}},
    )
    assert response.json() == {"status": "success", "id": "entry-1"}
    mocked_services["rag"].upsert_document.assert_awaited_once_with(
        id="entry-1", content="Shipped the RAG pipeline", metadata={"type": "journal_entry"}
    )


def test_upsert_email(client, mocked_services):
    response = client.post(
        "/api/upsert/email",
        json={
            "id": "msg-1",
            "content": "<p>Invoice attached</p>",
            "subject": "Invoice",
            "sender": "Alice <alice@example.com>",
            "date": "2026-01-01T09:00:00",
            "thread_id": "thread-1",
            "labels": ["INBOX"],
        },
    )
    assert response.json() == {"status": "success", "id": "msg-1"}
    kwargs = mocked_services["rag"].upsert_email.await_args.kwargs
    assert kwargs["email_id"] == "msg-1"
    assert kwargs["sender"] == "Alice <alice@example.com>"
    assert kwargs["labels"] == ["INBOX"]


def test_upsert_document_chunks_and_upserts(client, mocked_services, monkeypatch):
    from app.services import document_processor as document_processor_module

    def fake_process(content, filename, mime_type, metadata):
        assert content == b"plain text body"
        return [
            {"content": "chunk a", "metadata": dict(metadata)},
            {"content": "chunk b", "metadata": dict(metadata)},
        ]

    monkeypatch.setattr(
        document_processor_module.document_processor, "process_document", fake_process
    )

    response = client.post(
        "/api/upsert/document",
        json={
            "file_id": "file-1",
            "filename": "notes.txt",
            "mime_type": "text/plain",
            "content_base64": base64.b64encode(b"plain text body").decode(),
            "folder_path": "/Work",
        },
    )

    assert response.json() == {"status": "success", "id": "file-1", "chunks": 2}
    upserted_ids = [call.kwargs["id"] for call in mocked_services["rag"].upsert_document.await_args_list]
    assert upserted_ids == ["file-1_chunk_0", "file-1_chunk_1"]


def test_upsert_document_rejects_bad_base64(client):
    response = client.post(
        "/api/upsert/document",
        json={
            "file_id": "file-1",
            "filename": "notes.txt",
            "mime_type": "text/plain",
            "content_base64": "!!!not base64!!!",
        },
    )
    assert response.status_code == 400


def test_upsert_document_skips_when_no_text(client, monkeypatch):
    from app.services import document_processor as document_processor_module

    monkeypatch.setattr(
        document_processor_module.document_processor,
        "process_document",
        lambda **kwargs: [],
    )

    response = client.post(
        "/api/upsert/document",
        json={
            "file_id": "file-1",
            "filename": "empty.txt",
            "mime_type": "text/plain",
            "content_base64": base64.b64encode(b"   ").decode(),
        },
    )
    assert response.json()["status"] == "skipped"


def test_delete(client, mocked_services):
    response = client.request("DELETE", "/api/delete", json={"id": "entry-1"})
    assert response.json() == {"status": "success", "id": "entry-1"}
    mocked_services["rag"].delete_document.assert_awaited_once_with("entry-1")


def test_search(client, mocked_services):
    mocked_services["rag"].search_similar.return_value = [
        {"id": "entry-1", "score": 0.42, "metadata": {"type": "journal_entry"}, "content": "hi"}
    ]
    response = client.post("/api/search", json={"query": "rag", "top_k": 3})
    assert response.json()["results"][0]["id"] == "entry-1"
    mocked_services["rag"].search_similar.assert_awaited_once_with(
        query="rag", top_k=3, filter_conditions=None
    )


def test_search_rejects_out_of_range_top_k(client):
    assert client.post("/api/search", json={"query": "rag", "top_k": 99}).status_code == 422


def test_chat_uses_orchestrator(client, orchestrator):
    response = client.post("/api/chat", json={"message": "what did I do today?"})
    assert response.json()["response"] == "agent answer"
    orchestrator.process.assert_awaited_once()


def test_chat_falls_back_to_plain_rag(client, mocked_services, orchestrator):
    orchestrator.process.side_effect = RuntimeError("graph exploded")
    response = client.post("/api/chat", json={"message": "what did I do today?"})
    assert response.status_code == 200
    assert response.json()["response"] == "fallback answer"


def test_chat_reports_original_error_when_fallback_also_fails(client, mocked_services, orchestrator):
    orchestrator.process.side_effect = RuntimeError("graph exploded")
    mocked_services["rag"].process_query.side_effect = RuntimeError("qdrant down")
    response = client.post("/api/chat", json={"message": "hello"})
    assert response.status_code == 500
    assert "graph exploded" in response.json()["detail"]


def test_stats(client):
    body = client.get("/api/stats").json()
    assert body["collection"]["points_count"] == 3
    assert body["embedding_model"] == "all-MiniLM-L6-v2"
    assert body["llm_model"] == "llama3.2"


def test_lifespan_initializes_services(mocked_services):
    from fastapi.testclient import TestClient

    with TestClient(main.app):
        pass

    mocked_services["embedding"].initialize.assert_called_once()
    mocked_services["vector_db"].connect.assert_called_once()


def test_lifespan_survives_qdrant_being_down(mocked_services):
    from fastapi.testclient import TestClient

    mocked_services["vector_db"].connect.return_value = False

    with TestClient(main.app) as client:
        assert client.get("/health").status_code == 200


def test_stats_surfaces_failure(client, mocked_services):
    mocked_services["vector_db"].get_collection_info = AsyncMock(side_effect=RuntimeError("no collection"))
    response = client.get("/api/stats")
    assert response.status_code == 500


def test_datetime_fields_are_parsed(client, mocked_services):
    client.post(
        "/api/upsert/email",
        json={
            "id": "msg-2",
            "content": "body",
            "subject": "Subject",
            "sender": "bob@example.com",
            "date": "2026-02-03T10:30:00",
        },
    )
    assert mocked_services["rag"].upsert_email.await_args.kwargs["date"] == datetime(2026, 2, 3, 10, 30)
