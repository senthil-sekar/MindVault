//
//  EmbeddingService.swift
//  MindVault
//
//  Service for generating text embeddings.
//  Backend mode: calls /api/embed (all-MiniLM-L6-v2, 384-dim via Python backend).
//  Local mode:   uses NLEmbedding.sentenceEmbedding (on-device, no network).
//

import Foundation
import NaturalLanguage

@MainActor
class EmbeddingService: ObservableObject {
    static let shared = EmbeddingService()

    @Published var isProcessing = false
    @Published var lastError: String?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Generate Embedding  (routes by current llmMode)
    func generateEmbedding(for text: String) async throws -> [Float] {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let vector: [Float]
            if Configuration.llmMode == .localLLM {
                vector = try embedLocally(text)
            } else {
                vector = try await apiClient.embed(text: text)
            }
            lastError = nil
            return vector
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - On-Device Embedding  (NLEmbedding — built-in, no download, ~512-dim)
    func embedLocally(_ text: String) throws -> [Float] {
        guard let model = NLEmbedding.sentenceEmbedding(for: .english) else {
            throw EmbeddingError.modelUnavailable
        }
        guard let vector = model.vector(for: text) else {
            throw EmbeddingError.failedToEmbed
        }
        return vector.map { Float($0) }
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

// MARK: - Embedding Errors

enum EmbeddingError: LocalizedError {
    case modelUnavailable
    case failedToEmbed

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "On-device sentence embedding model is not available on this device."
        case .failedToEmbed:
            return "Failed to generate embedding for the provided text."
        }
    }
}
