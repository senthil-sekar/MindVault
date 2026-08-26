# Ollama Configuration Guide

## 🦙 Using Local Llama Models with Ollama

MindVault supports running 100% locally using Ollama for LLM inference. No API keys needed!

---

## Quick Setup

### 1. Install Ollama

**macOS:**
```bash
brew install ollama
```

**Or download from:** https://ollama.ai/download

### 2. Start Ollama Service

```bash
ollama serve
```

This starts Ollama on `http://localhost:11434`

### 3. Pull a Model

Choose one of these models:

**Recommended for Development (Fast):**
```bash
ollama pull llama3.2:3b
```

**Balanced (Good Quality & Speed):**
```bash
ollama pull llama3.2:8b
```

**Best Quality (Slower, requires more RAM):**
```bash
ollama pull llama3.1:70b
```

**Latest Llama 3.3:**
```bash
ollama pull llama3.3:70b
```

### 4. Configure MindVault Backend

Create/edit `backend/.env`:

```bash
# Ollama Configuration
OLLAMA_URL=http://localhost:11434
LLM_MODEL=llama3.2:3b

# Or use environment-specific URLs
# For Docker: OLLAMA_URL=http://host.docker.internal:11434
# For remote: OLLAMA_URL=http://your-server-ip:11434
```

### 5. Start Backend

```bash
cd backend
python3 -m uvicorn app.main:app --reload
```

---

## Available Models

| Model | Size | RAM Needed | Speed | Quality |
|-------|------|------------|-------|---------|
| llama3.2:1b | 1.3 GB | 4 GB | ⚡️⚡️⚡️ | ⭐️⭐️ |
| llama3.2:3b | 2 GB | 8 GB | ⚡️⚡️ | ⭐️⭐️⭐️ |
| llama3.2:8b | 4.7 GB | 16 GB | ⚡️ | ⭐️⭐️⭐️⭐️ |
| llama3.1:70b | 40 GB | 64 GB | 🐢 | ⭐️⭐️⭐️⭐️⭐️ |
| llama3.3:70b | 40 GB | 64 GB | 🐢 | ⭐️⭐️⭐️⭐️⭐️ |

**Recommendation:** Start with `llama3.2:3b` for fast development, upgrade to `llama3.2:8b` for production.

---

## Configuration Options

### Environment Variables

```bash
# Ollama Server URL
OLLAMA_URL=http://localhost:11434

# Model to use
LLM_MODEL=llama3.2:3b

# Generation parameters
LLM_MAX_TOKENS=2000
LLM_TEMPERATURE=0.7
```

### Docker Setup

If using Docker Compose, Ollama is already configured:

```bash
docker-compose up -d
```

The service uses `host.docker.internal:11434` to connect to your local Ollama.

---

## Testing Your Setup

### 1. Test Ollama Directly

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "Why is the sky blue?",
  "stream": false
}'
```

### 2. Test Backend Connection

```bash
cd backend
python3 test_backend.py
```

Look for:
```
✓ Ollama service is running
✓ LLM service initialized
✓ LLM generated response
```

### 3. Test in iOS App

1. Start backend: `./dev.sh start`
2. Open app in Xcode
3. Go to Chat tab
4. Ask a question
5. AI should respond using local Llama model!

---

## Common Ollama URLs

| Setup | URL |
|-------|-----|
| Local macOS/Linux | `http://localhost:11434` |
| Docker to host | `http://host.docker.internal:11434` |
| WSL to Windows | `http://$(hostname).local:11434` |
| Remote server | `http://your-ip:11434` |

---

## Troubleshooting

### "Connection refused"

**Check if Ollama is running:**
```bash
ollama list
```

**Start Ollama:**
```bash
ollama serve
```

### "Model not found"

**Pull the model:**
```bash
ollama pull llama3.2:3b
```

**List available models:**
```bash
ollama list
```

### Slow responses

1. Use a smaller model (llama3.2:3b)
2. Reduce `LLM_MAX_TOKENS` in config
3. Check available RAM
4. Close other applications

### Docker can't connect

Use `host.docker.internal` instead of `localhost`:
```bash
OLLAMA_URL=http://host.docker.internal:11434
```

---

## Performance Tips

### 1. Use Appropriate Model Size

- **8GB RAM:** llama3.2:1b or llama3.2:3b
- **16GB RAM:** llama3.2:3b or llama3.2:8b
- **32GB+ RAM:** Any model

### 2. Optimize Generation

```bash
# Faster but less creative
LLM_TEMPERATURE=0.3
LLM_MAX_TOKENS=1000

# Slower but more creative
LLM_TEMPERATURE=0.9
LLM_MAX_TOKENS=2000
```

### 3. Use GPU (if available)

Ollama automatically uses GPU if available. Check with:
```bash
ollama run llama3.2:3b "test"
```

---

## Model Selection Guide

### For Development
✅ **llama3.2:3b** - Fast, good enough for testing

### For Production
✅ **llama3.2:8b** - Best balance of speed and quality

### For Best Quality
✅ **llama3.1:70b** or **llama3.3:70b** - Professional quality (requires powerful machine)

---

## Alternative: OpenAI API

Not supported. `backend/app/services/llm.py` talks to Ollama's `/api/generate` only; there is no
OpenAI code path and no `LLM_PROVIDER` setting. Using a cloud model would mean implementing a new
client in that service.

---

## Resources

- **Ollama Docs:** https://github.com/ollama/ollama
- **Model Library:** https://ollama.ai/library
- **Llama Models:** https://ai.meta.com/llama/

---

## Quick Reference

```bash
# Install Ollama
brew install ollama

# Start Ollama
ollama serve

# Pull model
ollama pull llama3.2:3b

# Test model
ollama run llama3.2:3b "Hello!"

# Configure backend
echo "OLLAMA_URL=http://localhost:11434" >> backend/.env
echo "LLM_MODEL=llama3.2:3b" >> backend/.env

# Start MindVault
./dev.sh start
```

---

**🎉 You're now running 100% locally with Llama!**
