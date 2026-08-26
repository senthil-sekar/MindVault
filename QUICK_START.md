# Quick Start

Common commands and fixes. For the full picture see [README.md](README.md).

## First run

```bash
# 1. Local LLM
brew install ollama
ollama serve                 # leave running
ollama pull llama3.2         # must match LLM_MODEL in backend/.env

# 2. Backend + vector DB
cp backend/.env.example backend/.env
docker-compose up -d         # Qdrant on :6333, backend on :8000
curl http://localhost:8000/health

# 3. iOS app
open MindVault.xcodeproj     # then ⌘R
```

Healthy backend:

```json
{"status":"ok","vector_db_status":"connected","embeddings_ready":true,"timestamp":"..."}
```

## Everyday commands

| Task | Command |
|------|---------|
| Backend without Docker | `./dev.sh start` (uvicorn with reload on :8000) |
| Install backend deps | `./dev.sh setup` |
| Backend tests | `./dev.sh test` |
| Remove `__pycache__` / `.DS_Store` | `./dev.sh clean` |
| Backend logs | `docker-compose logs -f backend` |
| Restart backend only | `docker-compose restart backend` |
| Wipe the vector DB | `docker-compose down -v && docker-compose up -d` |
| Collection stats | `curl http://localhost:8000/api/stats` |
| Interactive API docs | http://localhost:8000/docs |
| Clean Xcode build | `./clean_build.sh` |

## Poking the API by hand

```bash
# Index something
curl -X POST http://localhost:8000/api/upsert \
  -H 'Content-Type: application/json' \
  -d '{"id":"test-1","content":"I shipped the RAG pipeline today.","metadata":{"type":"journal_entry","title":"Shipping","created_at":"2026-01-01"}}'

# Retrieve it
curl -X POST http://localhost:8000/api/search \
  -H 'Content-Type: application/json' -d '{"query":"what did I ship?","top_k":5}'

# Ask the agent graph
curl -X POST http://localhost:8000/api/chat \
  -H 'Content-Type: application/json' -d '{"message":"What did I ship recently?"}'
```

## Troubleshooting

**App can't reach the backend.** The simulator resolves `localhost` to itself, not your Mac, so
`Configuration.defaultServerURL` auto-detects the Mac's `en0` IP. If your IP changed, override it in
the app: **Profile → Settings → Server URL**. Plain-HTTP hosts other than `localhost` need an
`NSExceptionDomains` entry in `MindVault/Info.plist` (there's one for `192.168.1.24` today).

**`vector_db_status: disconnected`.** Qdrant isn't up or isn't reachable: `docker-compose ps`, then
`docker-compose up -d qdrant`. Inside Docker the backend uses `QDRANT_HOST=qdrant`; running the
backend on the host it needs `QDRANT_HOST=localhost`.

**Chat answers "I couldn't find relevant information".** Nothing matched. Check `/api/stats` shows a
non-zero `points_count`, and lower `RAG_MIN_SCORE` if needed.

**Chat replies "Sorry, I encountered an error".** Usually Ollama: confirm `ollama serve` is running
and `ollama list` contains the model named by `LLM_MODEL`. From Docker the backend reaches the host
Ollama via `http://host.docker.internal:11434`.

**Embedding dimension mismatch on upsert.** `EMBEDDING_DIMENSION` must match `EMBEDDING_MODEL`
(384 for `all-MiniLM-L6-v2`). Changing the model means recreating the collection
(`docker-compose down -v`).

**Gmail sync does nothing.** See [docs/ENABLING_EMAIL_FEATURES.md](docs/ENABLING_EMAIL_FEATURES.md).
