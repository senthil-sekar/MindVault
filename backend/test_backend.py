#!/usr/bin/env python3
"""
Test script for MindVault backend
Tests embedding, vector DB, and RAG functionality
"""

import asyncio
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services import embedding_service, vector_db_service, llm_service, rag_service
from app.config import get_settings


async def test_embedding_service():
    """Test embedding generation"""
    print("\n=== Testing Embedding Service ===")
    
    try:
        # Initialize
        embedding_service.initialize()
        assert embedding_service.is_ready(), "Embedding service not ready"
        print("✓ Embedding service initialized")
        
        # Generate embedding
        text = "I learned about Python and machine learning today"
        embedding = await embedding_service.generate_embedding(text)
        assert len(embedding) == 1536, f"Expected 1536 dimensions, got {len(embedding)}"
        print(f"✓ Generated embedding with {len(embedding)} dimensions")
        
        # Test batch embeddings
        texts = [
            "Python programming",
            "Machine learning",
            "Data science"
        ]
        embeddings = await embedding_service.generate_embeddings(texts)
        assert len(embeddings) == 3, "Expected 3 embeddings"
        print(f"✓ Generated {len(embeddings)} batch embeddings")
        
        return True
    except Exception as e:
        print(f"✗ Embedding test failed: {e}")
        return False


async def test_vector_db_service():
    """Test Qdrant operations"""
    print("\n=== Testing Vector DB Service ===")
    
    try:
        # Connect
        connected = vector_db_service.connect()
        assert connected, "Failed to connect to Qdrant"
        print("✓ Connected to Qdrant")
        
        # Check connection
        assert vector_db_service.is_connected(), "Not connected"
        print("✓ Connection verified")
        
        # Test upsert
        test_embedding = await embedding_service.generate_embedding("Test document")
        await vector_db_service.upsert(
            id="test_doc_1",
            vector=test_embedding,
            metadata={"type": "test", "title": "Test Document"},
            content="This is a test document"
        )
        print("✓ Document upserted successfully")
        
        # Test search
        query_embedding = await embedding_service.generate_embedding("Test")
        results = await vector_db_service.search(
            vector=query_embedding,
            top_k=5
        )
        assert len(results) > 0, "No search results"
        print(f"✓ Search returned {len(results)} results")
        
        # Test delete
        await vector_db_service.delete("test_doc_1")
        print("✓ Document deleted successfully")
        
        return True
    except Exception as e:
        print(f"✗ Vector DB test failed: {e}")
        return False


async def test_rag_service():
    """Test RAG pipeline"""
    print("\n=== Testing RAG Service ===")
    
    try:
        # Add sample documents
        sample_entries = [
            {
                "id": "entry_1",
                "content": "Today I learned Python programming. I built a web scraper and practiced data structures.",
                "metadata": {
                    "type": "journal_entry",
                    "category": "Education",
                    "title": "Learning Python",
                    "created_at": "2026-02-01"
                }
            },
            {
                "id": "entry_2",
                "content": "Working on machine learning project. Implemented a neural network using TensorFlow.",
                "metadata": {
                    "type": "journal_entry",
                    "category": "Work",
                    "title": "ML Project",
                    "created_at": "2026-02-05"
                }
            },
            {
                "id": "skill_1",
                "content": "Skill: Python. Expert level. 5+ years of experience in backend development, data science, and automation.",
                "metadata": {
                    "type": "skill",
                    "title": "Python",
                    "proficiency": 5
                }
            }
        ]
        
        # Upsert documents
        for entry in sample_entries:
            await rag_service.upsert_document(
                id=entry["id"],
                content=entry["content"],
                metadata=entry["metadata"]
            )
        print(f"✓ Upserted {len(sample_entries)} sample documents")
        
        # Test search
        results = await rag_service.search_similar("Python programming", top_k=3)
        assert len(results) > 0, "No search results"
        print(f"✓ Search found {len(results)} relevant documents")
        for result in results:
            print(f"  - {result.metadata.get('title', 'Untitled')} (score: {result.score:.3f})")
        
        # Test RAG query
        response, contexts = await rag_service.process_query(
            query="What programming skills do I have?",
            history=None
        )
        assert len(response) > 0, "Empty response"
        assert len(contexts) > 0, "No contexts returned"
        print(f"✓ RAG query successful")
        print(f"  Response: {response[:100]}...")
        print(f"  Used {len(contexts)} context documents")
        
        # Cleanup
        for entry in sample_entries:
            await rag_service.delete_document(entry["id"])
        print("✓ Cleaned up test documents")
        
        return True
    except Exception as e:
        print(f"✗ RAG test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


async def test_llm_service():
    """Test LLM service"""
    print("\n=== Testing LLM Service ===")
    
    try:
        # Initialize
        llm_service.initialize()
        assert llm_service.is_ready(), "LLM service not ready"
        print("✓ LLM service initialized")
        
        # Test simple response
        response = await llm_service.generate_simple_response(
            "Say 'Hello, MindVault!' and nothing else."
        )
        assert len(response) > 0, "Empty response"
        print(f"✓ Generated response: {response}")
        
        # Test response with context
        contexts = [
            "I have 5 years of Python experience",
            "I worked at a tech startup as a senior developer"
        ]
        response = await llm_service.generate_response(
            message="What's my experience with Python?",
            context=contexts,
            history=None
        )
        assert len(response) > 0, "Empty response"
        print(f"✓ Generated contextual response: {response[:100]}...")
        
        return True
    except Exception as e:
        print(f"✗ LLM test failed: {e}")
        return False


async def run_all_tests():
    """Run all tests"""
    print("=" * 60)
    print("MindVault Backend Test Suite")
    print("=" * 60)
    
    settings = get_settings()
    print(f"\nConfiguration:")
    print(f"  - Embedding Model: {settings.embedding_model}")
    print(f"  - LLM Model: {settings.llm_model}")
    print(f"  - Qdrant Host: {settings.qdrant_host}:{settings.qdrant_port}")
    print(f"  - OpenAI Key: {'✓ Set' if settings.openai_api_key else '✗ Not Set'}")
    
    if not settings.openai_api_key:
        print("\n⚠️  ERROR: OpenAI API key not set!")
        print("Please set OPENAI_API_KEY in your .env file")
        return False
    
    results = []
    
    # Run tests
    results.append(("Embedding Service", await test_embedding_service()))
    results.append(("Vector DB Service", await test_vector_db_service()))
    results.append(("LLM Service", await test_llm_service()))
    results.append(("RAG Service", await test_rag_service()))
    
    # Summary
    print("\n" + "=" * 60)
    print("Test Results Summary")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status}: {name}")
    
    print(f"\nPassed: {passed}/{total}")
    
    if passed == total:
        print("\n🎉 All tests passed! Backend is ready to use.")
        return True
    else:
        print("\n⚠️  Some tests failed. Check the errors above.")
        return False


if __name__ == "__main__":
    success = asyncio.run(run_all_tests())
    sys.exit(0 if success else 1)
