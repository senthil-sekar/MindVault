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

// MARK: - Local LLM Provider  (stub — wire llama.cpp or MLX-Swift here)
//
// To activate local inference:
//
// Option A — llama.cpp (all iPhones):
//   1. Add Swift package: https://github.com/ggerganov/llama.cpp  (tag: swift-*)
//   2. Replace the throw below with:
//        let ctx = try await LlamaContext.create(modelPath: modelPath)
//        return try await ctx.complete(systemPrompt: systemPrompt, userMessage: userMessage)
//
// Option B — MLX-Swift (Apple Silicon iPhones, A17+ recommended):
//   1. Add packages: https://github.com/ml-explore/mlx-swift-examples
//   2. Follow the LLMEval example to load a .gguf model from Documents.
//
// Model files: copy any Q4-quantized .gguf (Llama 3.2 1B ~700 MB, Phi-3 Mini ~2 GB)
// into the app's Documents folder via Files.app or iTunes File Sharing.

struct LocalLLMProvider: LLMProvider {
    let modelPath: String

    func complete(systemPrompt: String, userMessage: String, history: [[String: String]]) async throws -> String {
        throw LLMError.localModelNotInstalled
    }
}

// MARK: - Local Model Descriptor

struct LocalModel: Identifiable {
    let url: URL
    var id: String   { url.lastPathComponent }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var sizeString: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%d MB", bytes / 1_048_576)
    }

    /// Scans the app's Documents directory for .gguf model files.
    static var downloaded: [LocalModel] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ((try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        )) ?? [])
        .filter { $0.pathExtension == "gguf" }
        .map { LocalModel(url: $0) }
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
    case localModelNotInstalled

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
        case .localModelNotInstalled:
            return "No local model found. Copy a .gguf model file to the app's Documents folder."
        }
    }
}
