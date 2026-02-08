//
//  LLMService.swift
//  MindVault
//
//  Service for interacting with LLM for chat responses
//

import Foundation

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()
    
    @Published var isGenerating = false
    @Published var lastError: String?
    
    private let apiClient = APIClient.shared
    
    private init() {}
    
    // MARK: - Generate Response
    func generateResponse(
        message: String,
        context: [String],
        conversationHistory: [(role: String, content: String)] = []
    ) async throws -> String {
        isGenerating = true
        defer { isGenerating = false }
        
        // Build the prompt with context
        let contextPrompt = buildContextPrompt(context)
        let fullMessage = "\(contextPrompt)\n\nUser Question: \(message)"
        
        // Format conversation history
        let history = conversationHistory.map { ["role": $0.role, "content": $0.content] }
        
        do {
            let response = try await apiClient.chat(
                message: fullMessage,
                conversationHistory: history
            )
            lastError = nil
            return response.response
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Build Context Prompt
    private func buildContextPrompt(_ contexts: [String]) -> String {
        guard !contexts.isEmpty else {
            return "No relevant context found in the user's journal."
        }
        
        var prompt = "Here is relevant information from the user's personal journal and profile:\n\n"
        
        for (index, context) in contexts.enumerated() {
            prompt += "--- Context \(index + 1) ---\n\(context)\n\n"
        }
        
        prompt += "---\n\nBased on the above context, please answer the following question. If the context doesn't contain enough information to fully answer the question, say so and provide what you can based on available information."
        
        return prompt
    }
    
    // MARK: - Summarize Text
    func summarize(text: String, maxLength: Int = 200) async throws -> String {
        let prompt = "Please summarize the following text in \(maxLength) characters or less:\n\n\(text)"
        
        let response = try await apiClient.chat(message: prompt, conversationHistory: nil)
        return response.response
    }
    
    // MARK: - Generate Title
    func generateTitle(for content: String) async throws -> String {
        let prompt = "Generate a short, descriptive title (5-10 words) for this journal entry:\n\n\(content.prefix(500))"
        
        let response = try await apiClient.chat(message: prompt, conversationHistory: nil)
        return response.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Suggest Tags
    func suggestTags(for content: String) async throws -> [String] {
        let prompt = "Suggest 3-5 relevant tags for this journal entry. Return only the tags separated by commas, no explanations:\n\n\(content.prefix(500))"
        
        let response = try await apiClient.chat(message: prompt, conversationHistory: nil)
        let tags = response.response
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        
        return Array(tags.prefix(5))
    }
}
