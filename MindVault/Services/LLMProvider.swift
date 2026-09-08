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

// MARK: - Local LLM Provider  (MLX-Swift — A17 Pro+ iPhones)
//
// To activate on-device inference:
//   1. In Xcode → File → Add Package Dependencies:
//      https://github.com/ml-explore/mlx-swift-examples
//      Select the "MLXLM" library target.
//   2. The #if canImport(MLXLM) block below becomes active automatically.
//
// Model setup (one-time per model):
//   - Download a 4-bit quantized MLX model from Hugging Face, e.g.:
//       mlx-community/Llama-3.2-1B-Instruct-4bit   (~700 MB)
//       mlx-community/Phi-3.5-mini-instruct-4bit   (~2.2 GB)
//   - Copy the entire model folder (config.json + *.safetensors) to the
//     app's Documents directory via Files.app or Xcode → Devices.
//   - The folder appears in Settings → AI Mode → Local Model.

struct LocalLLMProvider: LLMProvider {
    let modelPath: String

    func complete(systemPrompt: String, userMessage: String, history: [[String: String]]) async throws -> String {
        guard !modelPath.isEmpty else { throw LLMError.noModelSelected }
        #if canImport(MLXLM)
        let modelURL = URL(fileURLWithPath: modelPath)
        let config = ModelConfiguration(directory: modelURL)
        let container = try await LLMModelFactory.shared.loadContainer(configuration: config)

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        messages.append(contentsOf: history)
        messages.append(["role": "user", "content": userMessage])

        let result = try await container.perform { context in
            let input = try await context.processor.prepare(input: .init(messages: messages))
            return try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: Float(Configuration.LLM.temperature)),
                context: context
            ) { _ in .more }
        }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw LLMError.emptyResponse }
        return output
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
        case .mlxPackageNotInstalled:
            return "MLX-Swift package not yet linked. Add mlx-swift-examples in Xcode → Add Package Dependencies."
        }
    }
}
