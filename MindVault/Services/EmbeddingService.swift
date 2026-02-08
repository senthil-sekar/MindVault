//
//  EmbeddingService.swift
//  MindVault
//
//  Service for generating text embeddings
//

import Foundation

@MainActor
class EmbeddingService: ObservableObject {
    static let shared = EmbeddingService()
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private let apiClient = APIClient.shared
    
    private init() {}
    
    // MARK: - Generate Embedding
    func generateEmbedding(for text: String) async throws -> [Float] {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let embedding = try await apiClient.embed(text: text)
            lastError = nil
            return embedding
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Batch Embeddings
    func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        isProcessing = true
        defer { isProcessing = false }
        
        var embeddings: [[Float]] = []
        
        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            embeddings.append(embedding)
        }
        
        return embeddings
    }
    
    // MARK: - Prepare Text for Embedding
    func prepareText(_ text: String, maxLength: Int = 8000) -> String {
        // Clean and truncate text for embedding
        var cleanedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
        
        // Truncate if too long
        if cleanedText.count > maxLength {
            cleanedText = String(cleanedText.prefix(maxLength))
            // Try to end at a sentence boundary
            if let lastPeriod = cleanedText.lastIndex(of: ".") {
                cleanedText = String(cleanedText[...lastPeriod])
            }
        }
        
        return cleanedText
    }
}
