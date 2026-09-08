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

> Most entries below apply to **AI Backend** mode. In **On-Device** mode there is no
> server, so backend/Qdrant/Ollama issues don't apply — see the On-Device section at
> the end. Check which mode you're in under **Profile → Settings → AI Mode**.

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

### On-Device mode

**"On-device inference isn't linked yet."** The MLX package isn't in the project. In Xcode:
**File → Add Package Dependencies…** → `https://github.com/ml-explore/mlx-swift-lm`
(Up to Next Major, from `3.31.3`) → add **MLXLLM** and **MLXLMCommon** to the MindVault
target. Needs Xcode 26+ (the package is swift-tools-version 6.2). Retrieval and embedding
work without it; only generation is blocked.

**"No local model selected."** Download one in **Settings → AI Mode → Browse Models**.
Start with Llama 3.2 3B (~1.8 GB) — the best speed/quality balance on an iPhone 16 Plus.

**Chat returns nothing relevant.** The on-device index is separate from the backend's
Qdrant. After switching to On-Device mode, run **Settings → Sync All Now** to index your
existing entries locally.

**Voice input fails with an on-device error.** The device or locale can't transcribe
on-device, and On-Device mode won't send audio to Apple's servers. Type the entry, or
switch AI mode if server-based dictation is acceptable to you.

**Download fails partway.** Downloads resume — re-tap Download and already-finished files
are skipped. Check free storage; models range from 0.7 GB to 4.1 GB.
