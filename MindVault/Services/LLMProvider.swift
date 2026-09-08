//
//  LLMProvider.swift
//  MindVault
//
//  LLM provider abstraction supporting backend (Ollama), BYOK (OpenAI), and on-device models.
//

import Foundation

// MARK: - Provider Mode

enum LLMProviderMode: String, CaseIterable {
    case backend  = "backend"
    case openAI   = "openai"
    case localLLM = "local"

    var displayName: String {
        switch self {
        case .backend:  return "AI Backend (Ollama)"
        case .openAI:   return "OpenAI (BYOK)"
        case .localLLM: return "On-Device Model"
        }
    }

    var description: String {
        switch self {
        case .backend:  return "Self-hosted backend with Ollama — Mac must be on the same network"
        case .openAI:   return "Your own OpenAI API key — fast, but uses the cloud"
        case .localLLM: return "100% on-device — fully private, works offline"
        }
    }

    var privacyLabel: String {
        switch self {
        case .backend:  return "Local Network"
        case .openAI:   return "Cloud (OpenAI)"
        case .localLLM: return "On-Device"
        }
    }

    var privacyIcon: String {
        switch self {
        case .backend:  return "wifi"
        case .openAI:   return "cloud"
        case .localLLM: return "iphone.and.arrow.forward"
        }
    }
}

// MARK: - Provider Protocol

protocol LLMProvider: Sendable {
    func complete(
        systemPrompt: String,
        userMessage: String,
        history: [[String: String]]
    ) async throws -> String
}

// MARK: - Backend Provider  (existing: iOS → Python backend → Ollama)

struct BackendLLMProvider: LLMProvider {
    func complete(systemPrompt: String, userMessage: String, history: [[String: String]]) async throws -> String {
        let request = ChatRequest(message: userMessage, history: history.isEmpty ? nil : history)
        return try await APIClient.shared.chat(request: request).response
    }
}

// MARK: - OpenAI Direct Provider  (BYOK — no backend required for LLM)

struct OpenAIDirectProvider: LLMProvider {
    let apiKey: String
    let model: String

    // Minimal Codable types — no SDK needed
    private struct RequestBody: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let max_tokens: Int
        let temperature: Double
    }

    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    func complete(systemPrompt: String, userMessage: String, history: [[String: String]]) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        var messages: [RequestBody.Message] = [.init(role: "system", content: systemPrompt)]
        for entry in history {
            if let role = entry["role"], let content = entry["content"] {
                messages.append(.init(role: role, content: content))
            }
        }
        messages.append(.init(role: "user", content: userMessage))

        let body = RequestBody(
            model: model,
            messages: messages,
            max_tokens: Configuration.LLM.maxTokens,
            temperature: Configuration.LLM.temperature
        )

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.networkError }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else { throw LLMError.emptyResponse }
            return content
        case 401:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        default:
            throw LLMError.serverError(http.statusCode)
        }
    }
}

// MARK: - Local LLM Provider  (MLX Swift — on-device inference)
//
// To activate on-device inference (one-time Xcode step), add TWO package
// dependencies — File → Add Package Dependencies… for each:
//
//   1. https://github.com/ml-explore/mlx-swift-lm        (Up to Next Major, from 3.31.3)
//      → add the "MLXLLM", "MLXLMCommon", and "MLXHuggingFace" library products.
//
//   2. https://github.com/huggingface/swift-transformers  (Up to Next Major, from 1.3.4)
//      → add the "Tokenizers" library product.
//
// The second package is easy to miss: mlx-swift-lm's tokenizer loader
// (#huggingFaceTokenizerLoader(), from MLXHuggingFace) expands to code that
// calls Tokenizers.AutoTokenizer directly, so swift-transformers has to be
// linked too even though nothing here imports it explicitly by name in the
// package graph — mlx-swift-lm does not declare it as a dependency.
//
// Once both are added, the #if canImport(MLXLMCommon) block below activates
// automatically — nothing else to change.
//
// Requires Xcode 26+ (mlx-swift-lm is swift-tools-version 6.2) and iOS 17+.
// Inference runs on the GPU via Metal, so an A17 Pro or newer device is
// recommended; older devices will run but slowly.
//
// Models are downloaded in-app via Settings → AI Mode → Browse Models.

#if canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// Keeps one model resident between messages — weights are multi-gigabyte,
/// so reloading per request would make chat unusable.
actor MLXModelCache {
    static let shared = MLXModelCache()

    private var loadedPath: String?
    private var loaded: ModelContainer?

    func container(forModelAt path: String) async throws -> ModelContainer {
        if let loaded, loadedPath == path { return loaded }
        let fresh = try await loadModelContainer(
            from: URL(fileURLWithPath: path),
            using: #huggingFaceTokenizerLoader()
        )
        loaded = fresh
        loadedPath = path
        return fresh
    }

    /// Free the weights, e.g. when the user switches or deletes a model.
    func evict() {
        loaded = nil
        loadedPath = nil
    }
}
#endif

/// Always-available entry point for controlling on-device model residency,
/// so callers don't need their own `#if canImport` guards.
enum LocalModelRuntime {
    /// Releases resident model weights (gigabytes of RAM). Call when the user
    /// switches to a different model or deletes the loaded one.
    static func unloadModel() async {
        #if canImport(MLXLMCommon)
        await MLXModelCache.shared.evict()
        #endif
    }
}

struct LocalLLMProvider: LLMProvider {
    let modelPath: String

    func complete(systemPrompt: String, userMessage: String, history: [[String: String]]) async throws -> String {
        guard !modelPath.isEmpty else { throw LLMError.noModelSelected }

        let dir = URL(fileURLWithPath: modelPath)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) else {
            throw LLMError.modelFilesMissing
        }

        #if canImport(MLXLMCommon)
        let container = try await MLXModelCache.shared.container(forModelAt: modelPath)
        let session = ChatSession(container, instructions: systemPrompt)

        let prior: [Chat.Message] = history.compactMap { entry in
            guard let role = entry["role"],
                  let content = entry["content"], !content.isEmpty else { return nil }
            switch role {
            case "assistant": return .assistant(content)
            case "system":    return .system(content)
            default:          return .user(content)
            }
        }

        let output: String
        if prior.isEmpty {
            output = try await session.respond(to: userMessage)
        } else {
            output = try await session.respond(to: prior + [.user(userMessage)])
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
        return trimmed
        #else
        throw LLMError.mlxPackageNotInstalled
        #endif
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case emptyResponse
    case networkError
    case serverError(Int)
    case noModelSelected
    case modelFilesMissing
    case mlxPackageNotInstalled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Add your OpenAI key in Settings → AI Mode."
        case .invalidAPIKey:
            return "Invalid OpenAI API key. Double-check it in Settings → AI Mode."
        case .rateLimited:
            return "OpenAI rate limit reached. Wait a moment and try again."
        case .emptyResponse:
            return "The model returned an empty response."
        case .networkError:
            return "Network error. Check your internet connection."
        case .serverError(let code):
            return "Server error (\(code)). Try again later."
        case .noModelSelected:
            return "No local model selected. Choose a model in Settings → AI Mode."
        case .modelFilesMissing:
            return "The selected model's files are missing or incomplete. Re-download it in Settings → AI Mode → Browse Models."
        case .mlxPackageNotInstalled:
            return "On-device inference isn't linked yet. In Xcode → Add Package Dependencies, add mlx-swift-lm (MLXLLM, MLXLMCommon, MLXHuggingFace) and swift-transformers (Tokenizers)."
        }
    }
}
