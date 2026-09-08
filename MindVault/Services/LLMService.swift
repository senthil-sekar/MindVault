//
//  LLMService.swift
//  MindVault
//
//  Resolves the LLM provider that matches the user's current AI Mode setting.
//

import Foundation

enum LLMService {
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
}
