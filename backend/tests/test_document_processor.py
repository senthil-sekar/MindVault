"""Text extraction and chunking in app.services.document_processor."""

import pytest

from app.services.document_processor import DocumentProcessor


@pytest.fixture
def processor():
    return DocumentProcessor(chunk_size=300, chunk_overlap=50)


def test_plain_text_document(processor):
    chunks = processor.process_document(
        content=b"Quarterly results were strong.",
        filename="notes.txt",
        mime_type="text/plain",
        metadata={"folder_path": "/Work"},
    )

    assert len(chunks) == 1
    assert chunks[0]["content"].startswith("Document: notes.txt")
    assert "Quarterly results were strong." in chunks[0]["content"]
    assert chunks[0]["metadata"]["folder_path"] == "/Work"
    assert chunks[0]["metadata"]["type"] == "document"
    assert chunks[0]["metadata"]["total_chunks"] == 1


def test_unsupported_mime_type(processor):
    with pytest.raises(ValueError, match="Unsupported document type"):
        processor.process_document(b"...", "sheet.numbers", "application/x-iwork", None)


def test_empty_document_yields_no_chunks(processor):
    assert processor.process_document(b"   \n  ", "blank.txt", "text/plain", None) == []


def test_long_document_is_chunked_with_stable_ids(processor):
    body = " ".join(f"Sentence {i} about revenue." for i in range(200)).encode()
    chunks = processor.process_document(body, "report.txt", "text/plain", None)

    assert len(chunks) > 1
    assert [c["metadata"]["chunk_index"] for c in chunks] == list(range(len(chunks)))
    assert all(c["metadata"]["total_chunks"] == len(chunks) for c in chunks)
    assert all(c["content"].startswith("Document: report.txt") for c in chunks)

    # Chunk IDs are derived from the content hash, so reprocessing overwrites
    # instead of duplicating.
    again = processor.process_document(body, "report.txt", "text/plain", None)
    assert [c["id"] for c in again] == [c["id"] for c in chunks]


def test_clean_text_removes_control_characters_and_ligatures(processor):
    assert processor._clean_text("ﬁrst\x07  line\n\n\n\nnext") == "first line next"
