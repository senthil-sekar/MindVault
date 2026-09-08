# MindVault 🧠

A personal AI-powered journal assistant that remembers everything about you. Write journal entries, record your skills, education, and experiences, and let your AI assistant answer questions about your life — entirely on your phone.

## Features

- 📝 **Personal Journal**: Write daily entries with categories, tags, and mood tracking
- 👤 **Profile Builder**: Record your skills, education, work experience, certifications, and more
- 🤖 **AI Chat**: Ask questions about your life, and get answers based on your journal
- 🎤 **Voice Support**: Speak your thoughts and have AI responses read aloud — dictation is always on-device, in both AI modes
- 📧 **Email Integration**: Connect Gmail, sync messages, and ask the AI about them in Chat (configurable in-app)
- 🔍 **RAG-Powered**: Retrieval-Augmented Generation — on-device embedding and vector search surface relevant context before the model answers
- 🔒 **Privacy by design**: No self-hosted backend, no server MindVault operates. Retrieval always runs on your phone; the only thing that ever leaves it is your question, and only if you choose BYOK
- 📱 **Runs standalone**: No Mac, no Docker, no server — the whole pipeline fits on the iPhone itself

## AI Modes

Pick a mode in **Profile → Settings → AI Mode**. There is no self-hosted backend and never
will be — MindVault doesn't host infrastructure for you. Retrieval (embedding + vector search)
always happens on-device in both modes; only generation differs:

| Mode | Retrieval | Generation | Leaves the device? |
|---|---|---|---|
| **On-Device** | `NLEmbedding` + `LocalVectorStore`, on-device | MLX running on the iPhone's GPU | **Never** |
| **OpenAI (BYOK)** | `NLEmbedding` + `LocalVectorStore`, on-device | OpenAI API, called directly from the phone with your key | Only your question + retrieved context, to OpenAI |

BYOK exists for people who want faster or more capable responses and are comfortable trading
some privacy for it — that's a choice you make per-query-session, not something the app decides
for you.

### On-Device mode

Everything runs on the phone:

- **Embeddings** — Apple's built-in `NLEmbedding.sentenceEmbedding`. No download, no network.
- **Vector search** — `LocalVectorStore`, a JSON-backed store with `vDSP` cosine similarity.
- **Generation** — [MLX](https://github.com/ml-explore/mlx-swift-lm) running a 4-bit quantized model on the GPU.
- **Dictation** — forced to on-device speech recognition, so audio is never uploaded.

Download models in-app from **Settings → AI Mode → Browse Models**. Curated options,
all verified to fit an iPhone 16 Plus (A18, 8 GB RAM):

| Model | Size | Tier |
|---|---|---|
| Llama 3.2 1B | ~0.7 GB | Fast |
| Gemma 3 1B | ~0.8 GB | Fast |
| **Llama 3.2 3B** | ~1.8 GB | **Balanced — recommended** |
| Qwen 2.5 3B | ~1.9 GB | Balanced |
| Phi 3.5 Mini | ~2.2 GB | Balanced |
| Gemma 3 4B | ~2.5 GB | Balanced |
| Mistral 7B | ~4.1 GB | Quality |

**One-time Xcode setup to enable on-device generation** — two packages, both via
**File → Add Package Dependencies…**:

1. `https://github.com/ml-explore/mlx-swift-lm` (Up to Next Major, from `3.31.3`)
   → add **MLXLLM**, **MLXLMCommon**, and **MLXHuggingFace** to the MindVault target
2. `https://github.com/huggingface/swift-transformers` (Up to Next Major, from `1.3.4`)
   → add **Tokenizers** to the MindVault target

The second package is easy to miss: mlx-swift-lm's tokenizer loader expands to code
that calls into `swift-transformers` directly, but mlx-swift-lm doesn't declare it as
a package dependency — Xcode won't pull it in for you.

**⚠️ MLX cannot run in the iOS Simulator — you need a physical device.** MLX requires a
Metal `MTLGPUFamily` the Simulator doesn't provide; trying anyway fails with `failed
assertion 'Dispatch Threads with Non-Uniform Threadgroup Size is not supported on this
device'`. That's a platform limitation, not a bug in this code. Options:
- Run on a physical iPhone (A17 Pro or newer for good performance)
- Add the **"Mac (Designed for iPad)"** destination in Xcode and run there instead —
  Apple Silicon Macs have a full Metal GPU
- Everything else (journal, profile, BYOK mode, retrieval) works fine in the Simulator
  as always; only MLX generation needs real Apple Silicon

**Memory:** iOS kills apps that use too much RAM ([jetsam](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)).
The larger catalog models (Gemma 3 4B, Mistral 7B) may need the
[Increased Memory Limit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_kernel_increased-memory-limit)
(Xcode → target → Signing & Capabilities → **+ Capability** → "Increased Memory Limit")
to avoid termination on devices where RAM would otherwise allow it. Not required for the
Fast-tier models (~0.7–0.8 GB).

Requires **Xcode 26+** (mlx-swift-lm is swift-tools-version 6.2) and iOS 17+. An A17 Pro
or newer device is recommended — inference runs on the GPU via Metal. Until both packages
are linked, the app builds and runs normally and On-Device mode reports that generation
isn't available yet; retrieval and embedding already work without it.

> Google Drive documents: MindVault indexes PDFs, Google Docs, and text files on-device using
> PDFKit. `.docx` / `.pptx` aren't supported — there's no backend to parse them.

## Architecture

```mermaid
graph TB
    subgraph iOS["MindVault — iOS App (SwiftUI + SwiftData)"]
        UI["User Interface<br/>Journal • Chat • Profile • Email • Drive"]

        subgraph Retrieval["On-Device Retrieval — always, both AI modes"]
            Embed["EmbeddingService<br/>NLEmbedding, on-device"]
            Store["LocalVectorStore<br/>JSON + vDSP cosine similarity"]
        end

        subgraph Generation["Generation — chosen in Settings → AI Mode"]
            MLX["MLX<br/>on-device LLM (GPU)"]
            OpenAIProvider["OpenAIDirectProvider<br/>BYOK"]
        end

        SwiftData["SwiftData<br/>journal, profile, email, accounts"]

        UI --> SwiftData
        UI --> Embed
        Embed --> Store
        Store --> MLX
        Store --> OpenAIProvider
    end

    subgraph CloudOptional["Cloud — only when you opt in"]
        OpenAIAPI["api.openai.com<br/>(BYOK mode only)"]
        Gmail["Gmail API<br/>(OAuth, read-only)"]
        Drive["Google Drive API<br/>(OAuth, read-only)"]
    end

    OpenAIProvider -.->|"HTTPS, your API key"| OpenAIAPI
    UI -.->|"optional"| Gmail
    UI -.->|"optional"| Drive

    style iOS fill:#e1f5ff,stroke:#01579b,stroke-width:3px
    style Retrieval fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style Generation fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style CloudOptional fill:#fff3e0,stroke:#e65100,stroke-width:2px
```

There is no backend and no server MindVault hosts for you. Everything under "iOS App" runs
inside the app process on the phone. The only network calls the app ever makes are: (1) OpenAI's
API, only in BYOK mode, only with your own key; (2) Hugging Face, only when you tap Download on a
model in Browse Models; (3) Google OAuth/Gmail/Drive, only if you connect those integrations.

### RAG Pipeline Flow

```mermaid
sequenceDiagram
    participant User
    participant iOS as iOS App
    participant Embed as NLEmbedding
    participant Store as LocalVectorStore
    participant Gen as MLX or OpenAI

    Note over User,Gen: 1. Indexing (journal entry, email, or document)
    User->>iOS: Write Journal Entry
    iOS->>Embed: Generate Embedding (on-device)
    Embed->>Store: Store Vector + Metadata
    Store-->>iOS: Indexed

    Note over User,Gen: 2. Query
    User->>iOS: Ask Question
    iOS->>Embed: Generate Query Embedding (on-device)
    Embed->>Store: Cosine Similarity Search
    Store-->>iOS: Top-K Results (with context)
    iOS->>Gen: Prompt + Context
    Note right of Gen: MLX — on-device GPU.<br/>OpenAI — HTTPS to api.openai.com, BYOK mode only.
    Gen-->>iOS: Generated Response
    iOS-->>User: Display Answer
```

### Data Flow Architecture

```mermaid
flowchart LR
    subgraph Input["📥 Data Input"]
        J[Journal Entry]
        P[Profile Item]
        E[Email Message]
        D[Drive Document]
        Q[User Query]
    end

    subgraph Processing["⚙️ On-Device Processing"]
        T[Text Cleaning /<br/>Chunking]
        V["NLEmbedding<br/>~512-dim"]
    end

    subgraph Storage["💾 On-Device Storage"]
        SD["SwiftData<br/>journal, profile, email, accounts"]
        LVS["LocalVectorStore<br/>JSON + vDSP"]
    end

    subgraph Retrieval["🔍 Retrieval"]
        S[Cosine Similarity Search]
        R[Top-K Ranking]
    end

    subgraph Generation["🤖 Generation"]
        C[Context Building]
        L["MLX (on-device) or<br/>OpenAI API (BYOK)"]
        A[Answer]
    end

    J --> T
    P --> T
    E --> T
    D --> T
    T --> V
    V --> LVS
    T --> SD

    Q --> V
    V --> S
    S --> LVS
    LVS --> R
    R --> C
    C --> L
    L --> A

    style Input fill:#e3f2fd,stroke:#1565c0
    style Processing fill:#f3e5f5,stroke:#6a1b9a
    style Storage fill:#fff3e0,stroke:#ef6c00
    style Retrieval fill:#e8f5e9,stroke:#2e7d32
    style Generation fill:#fce4ec,stroke:#c2185b
```

## Prerequisites

- **Xcode 15+**, iOS 17+ deployment target
- **Xcode 26+** and a physical iPhone (A17 Pro+ recommended) if you want On-Device generation —
  see [On-Device mode](#on-device-mode) for why
- Nothing else. No Python, no Docker, no server to run — the app builds and runs standalone

## Quick Start

```bash
git clone <repo-url>
cd MindVault
open MindVault.xcodeproj
```

Then in Xcode: select a device or simulator, and build & run (⌘R).

**First launch:** the app defaults to **On-Device** mode. Go to **Profile → Settings → AI Mode
→ Browse Models** to download a model (Llama 3.2 3B is the recommended default) — see
[On-Device mode](#on-device-mode) above for the one-time Xcode package setup that enables
generation. Prefer **OpenAI (BYOK)** instead? Switch AI Mode and paste your API key; no
Xcode setup needed for that path.

**Optional — Gmail/Drive integration:**
```bash
cp Config.local.xcconfig.example Config.local.xcconfig
# then set GOOGLE_OAUTH_CLIENT_ID_PREFIX — see docs/ENABLING_EMAIL_FEATURES.md
```
Skip this and the app runs fine with those integrations disabled.

## Project Structure

```
MindVault/
├── MindVault/                    # iOS App — this is the whole product
│   ├── MindVaultApp.swift        # App entry point
│   ├── ContentView.swift         # Main content view
│   ├── Models/                   # SwiftData models
│   │   ├── JournalEntry.swift
│   │   ├── ProfileItem.swift
│   │   └── ChatMessage.swift
│   ├── Views/                    # SwiftUI views
│   │   ├── Journal/
│   │   ├── Chat/
│   │   └── Profile/
│   │       ├── ProfileView.swift        # Includes SettingsView (AI Mode)
│   │       └── ModelBrowserView.swift   # Download/select on-device models
│   ├── Services/
│   │   ├── EmbeddingService.swift       # On-device embeddings (NLEmbedding)
│   │   ├── VectorDBService.swift        # Wraps LocalVectorStore: embed + upsert/search
│   │   ├── LocalVectorStore.swift       # On-device vectors + vDSP search
│   │   ├── LLMProvider.swift            # OpenAI (BYOK) / MLX (on-device) providers
│   │   ├── ModelCatalog.swift           # Model catalog + Hugging Face downloader
│   │   ├── LLMService.swift             # Resolves the active provider from AI Mode
│   │   └── RAGService.swift             # Retrieval + generation orchestration
│   └── Utilities/
│       └── Configuration.swift
│
└── mcp-server/                   # Standalone MCP server (Google Drive tools)
    └── src/index.ts              # Not used by the iOS app — DriveService.swift talks to
                                   # Google Drive directly. This exposes the same capability
                                   # as MCP tools for use from an MCP client (e.g. Claude
                                   # Desktop) instead.
```

## Configuration

### iOS App Settings

Navigate to Profile → Settings in the app to configure:

- **AI Mode**: On-Device / OpenAI (BYOK) — see [AI Modes](#ai-modes) above
- **OpenAI API Key**: Stored in the iOS Keychain, never in UserDefaults (BYOK mode)
- **Browse Models**: Download and select on-device MLX models (On-Device mode)
- **Auto-sync**: Automatically sync new entries to AI
- **Sync All Now / Clear AI Data**: Re-index or wipe the search index (journal entries themselves are untouched)
- **Email Accounts**: Connect Gmail with one tap
  - Users just click "Connect Gmail Account" and authorize
  - Emails are automatically synced and indexed on-device for Chat context
  - No manual configuration needed by users

**Developer Setup (One-time):**
The Google OAuth client ID is a build setting, not something hardcoded in source — see
[docs/ENABLING_EMAIL_FEATURES.md](docs/ENABLING_EMAIL_FEATURES.md) for the 5-minute version, or
[docs/EMAIL_CONFIGURATION_GUIDE.md](docs/EMAIL_CONFIGURATION_GUIDE.md) for the full walkthrough:
1. [Google Cloud Console](https://console.cloud.google.com/apis/credentials) → create project →
   enable Gmail API → create an iOS OAuth Client ID
2. `cp Config.local.xcconfig.example Config.local.xcconfig` and set `GOOGLE_OAUTH_CLIENT_ID`
   there (gitignored — never committed)
3. Users can then connect their Gmail accounts seamlessly, no source changes needed

## Usage Examples

### Adding Journal Entries

1. Tap the **+** button in the Journal tab
2. Write your entry (or use voice input)
3. Select a category and add tags
4. Optionally track your mood
5. Save - the entry will be automatically synced to AI

### Asking Questions

Try questions like:
- "What are my top skills?"
- "Summarize my career journey"
- "What were my goals this year?"
- "Am I qualified for a senior developer role?"
- "What patterns do you see in my journal?"

### Building Your Profile

Add comprehensive profile items:
- **Skills**: Programming languages, tools, soft skills
- **Education**: Degrees, certifications, bootcamps
- **Experience**: Jobs, roles, responsibilities
- **Projects**: Personal and professional projects
- **Achievements**: Awards, milestones, accomplishments

## Development

### Running Tests

```bash
# iOS: no test target exists yet (MindVault.xcodeproj has a single
# PBXNativeTarget, the app itself). Verify iOS changes by building and
# running in Xcode.
```

### Running the MCP Server

Optional — the iOS app doesn't use this; it exposes the same Google Drive capability as
`DriveService.swift` for use from an MCP client instead.

```bash
cd mcp-server
npm install
npm run build   # tsc — this is what CI runs
npm start        # or: npm run dev  (tsx watch)
```

## Privacy & Security

- No self-hosted backend, no server MindVault operates — there's nothing to trust beyond
  the app itself, Apple's frameworks, and whichever cloud API you explicitly opt into
- API keys are stored securely in iOS Keychain and never logged
- Email OAuth tokens are hardware-encrypted in Keychain
- Dictation always uses on-device speech recognition, in both AI modes — MindVault refuses
  to fall back to Apple's servers rather than silently uploading audio

What leaves the device depends on the AI mode:

- **On-Device** — nothing. Embedding, search, and generation all run on the phone.
- **OpenAI (BYOK)** — your question and the retrieved context are sent to OpenAI to generate
  each answer. Retrieval itself (embedding, search) still runs on-device — only that one
  generation call leaves the phone, and only because you chose BYOK.

## Documentation

For detailed guides, see the `docs/` folder:

- **[QUICK_START.md](QUICK_START.md)** - Quick reference for common tasks and troubleshooting
- **[EMAIL_CONFIGURATION_GUIDE.md](docs/EMAIL_CONFIGURATION_GUIDE.md)** - Step-by-step Gmail integration setup
- **[ENABLING_EMAIL_FEATURES.md](docs/ENABLING_EMAIL_FEATURES.md)** - How to enable email features (5 minutes)

## Roadmap

### Completed ✅
- [x] Voice input and output (Speech-to-text & Text-to-speech)
- [x] Email integration (Gmail OAuth, in-app configuration)
- [x] Secure credential storage (iOS Keychain)
- [x] BYOK mode (bring your own OpenAI key)
- [x] On-device embeddings (`NLEmbedding`)
- [x] On-device vector store (vDSP cosine similarity)
- [x] On-device LLM generation (MLX) with in-app model downloads
- [x] Fully standalone — no backend, no server, no Mac required

### Coming Soon
- [ ] iCloud sync for journal entries
- [ ] Apple Watch companion app
- [ ] Siri integration
- [ ] Export/import functionality
- [ ] Multiple AI personas
- [ ] Advanced analytics and insights
- [ ] Email auto-summarization
- [ ] Background email sync

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests.

---

Built with ❤️ using SwiftUI, SwiftData, and MLX
