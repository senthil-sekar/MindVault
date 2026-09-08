# Quick Start

Common commands and fixes. For the full picture see [README.md](README.md).

## First run

```bash
git clone <repo-url>
cd MindVault
open MindVault.xcodeproj     # then ⌘R
```

No backend, no Docker, no server — the app builds and runs standalone. It defaults to
**On-Device** mode; go to **Profile → Settings → AI Mode → Browse Models** to download a model
(see [On-Device mode setup](README.md#on-device-mode) for the one-time Xcode package step that
enables generation). Prefer **OpenAI (BYOK)**? Switch AI Mode in Settings and paste your API
key — no Xcode setup needed for that path.

## Everyday commands

| Task | Command |
|------|---------|
| Clean Xcode build | `./clean_build.sh` |
| Build the MCP server (optional, unused by the app) | `cd mcp-server && npm install && npm run build` |

## Troubleshooting

Check which AI mode you're in under **Profile → Settings → AI Mode** — most issues below are
specific to one mode.

**Chat answers "I couldn't find relevant information."** Nothing matched in
`LocalVectorStore`. Run **Settings → Sync All Now** to (re-)index your journal, profile, emails,
and Drive documents.

**Gmail sync does nothing.** See [docs/ENABLING_EMAIL_FEATURES.md](docs/ENABLING_EMAIL_FEATURES.md).

**BYOK: "No API key configured."** Paste an OpenAI API key in **Settings → AI Mode → OpenAI
API Key**. It's stored in the iOS Keychain.

**BYOK: "Invalid OpenAI API key" / 401.** Double-check the key in Settings; regenerate it in the
OpenAI dashboard if needed.

### On-Device mode

**"On-device inference isn't linked yet."** Two packages are missing — both via Xcode's
**File → Add Package Dependencies…**:
1. `https://github.com/ml-explore/mlx-swift-lm` (Up to Next Major, from `3.31.3`) →
   add **MLXLLM**, **MLXLMCommon**, **MLXHuggingFace**
2. `https://github.com/huggingface/swift-transformers` (Up to Next Major, from `1.3.4`) →
   add **Tokenizers**

Both are required — mlx-swift-lm's tokenizer loader needs `swift-transformers` but
doesn't pull it in automatically. Needs Xcode 26+ (mlx-swift-lm is swift-tools-version
6.2). Retrieval and embedding work without either package; only generation is blocked.

**"Dispatch Threads with Non-Uniform Threadgroup Size is not supported on this device."**
You're running in the iOS Simulator. MLX needs a real Metal GPU and cannot run there at
all — this isn't fixable in code. Run on a physical device (A17 Pro+ recommended), or add
the "Mac (Designed for iPad)" destination in Xcode and run on an Apple Silicon Mac instead.

**App gets killed while loading a model.** iOS terminates apps that exceed their memory
budget (jetsam). Add the Increased Memory Limit capability: Xcode → target → Signing &
Capabilities → **+ Capability** → "Increased Memory Limit". More likely with the larger
catalog models (Gemma 3 4B, Mistral 7B) than the ~0.7–0.8 GB Fast-tier ones.

**"No local model selected."** Download one in **Settings → AI Mode → Browse Models**.
Start with Llama 3.2 3B (~1.8 GB) — the best speed/quality balance on an iPhone 16 Plus.

**Voice input fails with an on-device error.** The device or locale can't transcribe
on-device, and MindVault never sends audio to Apple's servers, in either AI mode. Type
the entry instead.

**Download fails partway.** Downloads resume — re-tap Download and already-finished files
are skipped. Check free storage; models range from 0.7 GB to 4.1 GB.
