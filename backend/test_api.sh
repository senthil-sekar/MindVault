#!/bin/bash
# API Testing Script for MindVault Backend

BASE_URL="http://localhost:8000"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "MindVault Backend API Tests"
echo "=========================================="

# Test 1: Health Check
echo -e "\n${YELLOW}Test 1: Health Check${NC}"
response=$(curl -s -w "\n%{http_code}" $BASE_URL/health)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Health check passed${NC}"
    echo "$body" | python3 -m json.tool
else
    echo -e "${RED}✗ Health check failed (HTTP $http_code)${NC}"
    exit 1
fi

# Test 2: Generate Embedding
echo -e "\n${YELLOW}Test 2: Generate Embedding${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "This is a test document about Python programming"}')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Embedding generation passed${NC}"
    embedding_length=$(echo "$body" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['embedding']))")
    echo "  Embedding dimension: $embedding_length"
else
    echo -e "${RED}✗ Embedding generation failed (HTTP $http_code)${NC}"
    echo "$body"
    exit 1
fi

# Test 3: Upsert Document
echo -e "\n${YELLOW}Test 3: Upsert Document${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/upsert \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test_doc_1",
    "content": "I am a skilled Python developer with 5 years of experience in backend development and machine learning.",
    "metadata": {
      "type": "skill",
      "title": "Python Development",
      "proficiency": 5
    }
  }')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Document upsert passed${NC}"
    echo "$body" | python3 -m json.tool
else
    echo -e "${RED}✗ Document upsert failed (HTTP $http_code)${NC}"
    echo "$body"
    exit 1
fi

# Test 4: Search Documents
echo -e "\n${YELLOW}Test 4: Search Documents${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Python programming skills",
    "top_k": 5
  }')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Search passed${NC}"
    num_results=$(echo "$body" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['results']))")
    echo "  Found $num_results results"
    echo "$body" | python3 -m json.tool
else
    echo -e "${RED}✗ Search failed (HTTP $http_code)${NC}"
    echo "$body"
    exit 1
fi

# Test 5: Chat with RAG
echo -e "\n${YELLOW}Test 5: Chat with RAG${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST $BASE_URL/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What are my programming skills?",
    "history": []
  }')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Chat passed${NC}"
    echo "$body" | python3 -c "import sys, json; data = json.load(sys.stdin); print('Response:', data['response'][:200] + '...'); print('Contexts:', len(data['contexts']))"
else
    echo -e "${RED}✗ Chat failed (HTTP $http_code)${NC}"
    echo "$body"
    exit 1
fi

# Test 6: Get Stats
echo -e "\n${YELLOW}Test 6: Get Stats${NC}"
response=$(curl -s -w "\n%{http_code}" $BASE_URL/api/stats)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Stats retrieval passed${NC}"
    echo "$body" | python3 -m json.tool
else
    echo -e "${RED}✗ Stats retrieval failed (HTTP $http_code)${NC}"
    echo "$body"
fi

# Test 7: Delete Document
echo -e "\n${YELLOW}Test 7: Delete Document${NC}"
response=$(curl -s -w "\n%{http_code}" -X DELETE $BASE_URL/api/delete \
  -H "Content-Type: application/json" \
  -d '{"id": "test_doc_1"}')
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Document deletion passed${NC}"
    echo "$body" | python3 -m json.tool
else
    echo -e "${RED}✗ Document deletion failed (HTTP $http_code)${NC}"
    echo "$body"
fi

echo -e "\n=========================================="
echo -e "${GREEN}All API tests passed!${NC}"
echo "=========================================="
