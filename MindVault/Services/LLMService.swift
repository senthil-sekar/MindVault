//
//  LLMService.swift
//  MindVault
//
//  Dispatches LLM calls to the active provider (backend, OpenAI BYOK, or local model).
//

import Foundation

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    @Published var isGenerating = false
    @Published var lastError: String?

    private init() {}

    // MARK: - Active Provider

    /// Returns the provider that matches the user's current AI Mode setting.
    static var activeProvider: any LLMProvider {
        switch Configuration.llmMode {
        case .backend:
            return BackendLLMProvider()
        case .openAI:
            let key = (try? KeychainService.shared.retrieveAPIKey(for: "openai")) ?? ""
            return OpenAIDirectProvider(apiKey: key, model: Configuration.BYOK.openAIModel)
        case .localLLM:
            return LocalLLMProvider(modelPath: Configuration.BYOK.localModelPath)
        }
    }

    // MARK: - Generate Response (with RAG context)

    func generateResponse(
        message: String,
        context: [String],
        conversationHistory: [(role: String, content: String)] = []
    ) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }

        let contextPrompt = buildContextPrompt(context)
        let fullMessage = "\(contextPrompt)\n\nUser Question: \(message)"
        let history = conversationHistory.map { ["role": $0.role, "content": $0.content] }

        do {
            let response = try await LLMService.activeProvider.complete(
                systemPrompt: Configuration.LLM.systemPrompt,
                userMessage: fullMessage,
                history: history
            )
            lastError = nil
            return response
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Summarize

    func summarize(text: String, maxLength: Int = 200) async throws -> String {
        let msg = "Summarize the following text in \(maxLength) characters or less:\n\n\(text)"
        return try await LLMService.activeProvider.complete(
            systemPrompt: Configuration.LLM.systemPrompt,
            userMessage: msg,
            history: []
        )
    }

    // MARK: - Generate Title

    func generateTitle(for content: String) async throws -> String {
        let msg = "Generate a short, descriptive title (5-10 words) for this journal entry:\n\n\(content.prefix(500))"
        let response = try await LLMService.activeProvider.complete(
            systemPrompt: Configuration.LLM.systemPrompt,
            userMessage: msg,
            history: []
        )
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Suggest Tags

    func suggestTags(for content: String) async throws -> [String] {
        let msg = "Suggest 3-5 relevant tags for this journal entry. Return only the tags separated by commas, no explanations:\n\n\(content.prefix(500))"
        let response = try await LLMService.activeProvider.complete(
            systemPrompt: Configuration.LLM.systemPrompt,
            userMessage: msg,
            history: []
        )
        return response
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
            .prefix(5)
            .map { String($0) }
    }

    // MARK: - Context Prompt Builder

    private func buildContextPrompt(_ contexts: [String]) -> String {
        guard !contexts.isEmpty else {
            return "No relevant context found in the user's journal."
        }
        var prompt = "Here is relevant information from the user's personal journal and profile:\n\n"
        for (i, ctx) in contexts.enumerated() {
            prompt += "--- Context \(i + 1) ---\n\(ctx)\n\n"
        }
        prompt += "---\n\nBased on the above context, please answer the following question. If the context doesn't contain enough information, say so."
        return prompt
    }
}
