#!/bin/bash
# Quick diagnostic script to check MindVault email sync status

echo "🔍 MindVault Email Sync Diagnostics"
echo "===================================="
echo ""

# Check backend health
echo "1️⃣ Backend Health Check:"
curl -s http://localhost:8000/health | python3 -m json.tool | head -10
echo ""

# Check vector DB document count
echo "2️⃣ Vector DB Document Count:"
curl -s http://localhost:6333/collections/mindvault | python3 -m json.tool | grep -A 1 "points_count"
echo ""

# Search for emails
echo "3️⃣ Searching for emails in vector DB:"
curl -s -X POST http://localhost:8000/api/search \
  -H "Content-Type: application/json" \
  -d '{"query":"email","top_k":5}' | python3 -m json.tool | grep -E "(id|subject|score)" | head -20
echo ""

# Test chat
echo "4️⃣ Testing chat with email query:"
curl -s -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"How many emails do I have?"}' | python3 -m json.tool | grep -A 5 "response"
echo ""

echo "===================================="
echo "✅ Diagnostic complete!"
echo ""
echo "Expected results:"
echo "  - Backend status: ok"
echo "  - Document count: > 1 (currently should be 25+)"
echo "  - Search results: Multiple emails with real subjects"
echo "  - Chat response: Should mention actual email count"
echo ""
echo "If you see only 1 document and test data:"
echo "  → Click 'Process for AI' button in the Email tab!"
