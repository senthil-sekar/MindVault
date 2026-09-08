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
// To activate on-device inference (one-time Xcode step):
//   1. File → Add Package Dependencies…
//        https://github.com/ml-explore/mlx-swift-lm      (Up to Next Major, 3.31.3)
//   2. Add the "MLXLLM" and "MLXLMCommon" library products to the MindVault target.
//   3. The #if canImport(MLXLMCommon) block below activates automatically.
//
// Requires Xcode 26+ (the package is swift-tools-version 6.2) and iOS 17+.
// Inference runs on the GPU via Metal, so an A17 Pro or newer device is
// recommended; older devices will run but slowly.
//
// Models are downloaded in-app via Settings → AI Mode → Browse Models.

#if canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon

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
            using: TokenizersLoader()
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

// MARK: - Local Model Descriptor

/// Represents an MLX model folder in the app's Documents directory.
/// An MLX model is a folder containing config.json + *.safetensors weight files.
struct LocalModel: Identifiable {
    let url: URL
    var id: String   { url.lastPathComponent }
    var name: String { url.lastPathComponent }
    var sizeString: String {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) else { return "?" }
        var totalBytes = 0
        for case let fileURL as URL in enumerator {
            totalBytes += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        let gb = Double(totalBytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%d MB", totalBytes / 1_048_576)
    }

    /// Scans Documents for subdirectories that look like MLX model folders
    /// (contain config.json and at least one .safetensors file).
    static var downloaded: [LocalModel] {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirs = (try? fm.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        return dirs.filter { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
            let hasConfig = fm.fileExists(atPath: url.appendingPathComponent("config.json").path)
            let hasSafetensors = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? [])
                .contains { $0.hasSuffix(".safetensors") }
            return hasConfig && hasSafetensors
        }.map { LocalModel(url: $0) }
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
            return "On-device inference isn't linked yet. Add the mlx-swift-lm package (MLXLLM + MLXLMCommon) in Xcode → Add Package Dependencies."
        }
    }
}
