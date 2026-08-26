"""Cleaning and chunking rules in app.services.email_processor."""

from datetime import datetime

import pytest

from app.services.email_processor import EmailProcessor


@pytest.fixture
def processor():
    return EmailProcessor(chunk_size=200, chunk_overlap=50)


@pytest.mark.parametrize(
    "sender,expected",
    [
        ("Alice Smith <alice@example.com>", ("Alice Smith", "alice@example.com")),
        ('"Alice Smith" <alice@example.com>', ("Alice Smith", "alice@example.com")),
        ("bob@example.com", ("bob", "bob@example.com")),
        ("no-address-here", ("no-address-here", "no-address-here")),
    ],
)
def test_parse_sender(processor, sender, expected):
    assert processor._parse_sender(sender) == expected


def test_strip_html(processor):
    html = (
        "<html><style>p{color:red}</style><script>evil()</script>"
        "<p>Hello&nbsp;&amp; welcome</p><br><div>Line&#33;</div></html>"
    )
    text = processor._strip_html(html)
    assert "evil()" not in text
    assert "color:red" not in text
    assert "Hello & welcome" in text
    assert "Line!" in text


def test_removes_signature(processor):
    body = "The report is ready.\n\nBest regards,\nAlice\nCEO, Example Inc"
    assert processor._clean_email_body(body) == "The report is ready."


def test_removes_disclaimer(processor):
    body = "Numbers look good.\nThis email is intended solely for the addressee."
    assert "intended solely" not in processor._clean_email_body(body)


def test_removes_quoted_reply(processor):
    body = "Sounds good.\n\nOn Mon, Jan 1, 2026 at 9:00 AM Alice wrote:\nOriginal question?"
    cleaned = processor._clean_email_body(body)
    assert cleaned == "Sounds good."


def test_normalize_whitespace(processor):
    assert processor._normalize_whitespace("\n\na  b\n\n\n\nc  \n\n") == "a b\n\nc"


@pytest.mark.parametrize(
    "subject,is_reply,is_forward",
    [("Re: Invoice", True, False), ("Fwd: Invoice", False, True), ("Invoice", False, False)],
)
def test_subject_type_detection(processor, subject, is_reply, is_forward):
    assert processor._is_reply(subject) is is_reply
    assert processor._is_forward(subject) is is_forward


def test_short_email_becomes_one_chunk_with_context_header(processor):
    result = processor.process_email(
        raw_content="<p>Invoice 42 is attached.</p>",
        email_id="msg-1",
        subject="Invoice 42",
        sender="Alice Smith <alice@example.com>",
        date=datetime(2026, 1, 1, 9, 0),
        thread_id="thread-1",
        labels=["INBOX", "IMPORTANT"],
    )

    assert len(result.chunks) == 1
    chunk = result.chunks[0]
    assert chunk.chunk_id == "msg-1_0"
    assert "Invoice 42" in chunk.content
    assert "Alice Smith" in chunk.content
    assert chunk.metadata["thread_id"] == "thread-1"
    assert chunk.metadata["labels"] == ["INBOX", "IMPORTANT"]
    assert result.sender_email == "alice@example.com"


def test_long_email_is_split_into_numbered_chunks(processor):
    body = " ".join(f"Sentence number {i} about the quarterly numbers." for i in range(60))
    result = processor.process_email(
        raw_content=body,
        email_id="msg-2",
        subject="Quarterly",
        sender="alice@example.com",
        date=datetime(2026, 1, 1, 9, 0),
    )

    assert len(result.chunks) > 1
    assert [c.chunk_index for c in result.chunks] == list(range(len(result.chunks)))
    assert all(c.total_chunks == len(result.chunks) for c in result.chunks)
    assert all("Quarterly" in c.content for c in result.chunks)
