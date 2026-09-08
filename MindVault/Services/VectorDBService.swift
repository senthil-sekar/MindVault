//
//  VectorDBService.swift
//  MindVault
//
//  Service for interacting with the vector database
//

import Foundation

@MainActor
class VectorDBService: ObservableObject {
    static let shared = VectorDBService()
    
    @Published var isConnected = false
    @Published var documentCount = 0
    @Published var lastError: String?
    
    private let apiClient = APIClient.shared
    
    private init() {}
    
    /// True when the app indexes and searches entirely on-device.
    private var isLocal: Bool { Configuration.llmMode == .localLLM }

    // MARK: - Connection Check
    func checkConnection() async {
        // In local mode there is no server to reach — the on-device store is always available.
        guard !isLocal else {
            isConnected = true
            documentCount = LocalVectorStore.shared.documentCount
            lastError = nil
            return
        }
        do {
            let health = try await apiClient.checkHealth()
            isConnected = health.status == "ok" && health.vectorDbStatus == "connected"
            lastError = nil
        } catch {
            isConnected = false
            lastError = error.localizedDescription
        }
    }

    // MARK: - Upsert Document
    func upsert(id: String, content: String, type: String, metadata: [String: Any]) async throws {
        if isLocal {
            let title = (metadata["title"] as? String)
                ?? (metadata["subject"] as? String)
                ?? type
            let vector = try EmbeddingService.shared.embedLocally(content)
            // Preserve caller metadata (thread_id, file_id, chunk, from, date…)
            // rather than dropping everything but the title.
            var flat: [String: String] = [:]
            for (key, value) in metadata where key != "title" {
                if let array = value as? [String] {
                    flat[key] = array.joined(separator: ", ")
                } else {
                    flat[key] = String(describing: value)
                }
            }
            LocalVectorStore.shared.upsert(LocalVectorStore.VectorDocument(
                id: id, type: type, title: title,
                content: content, vector: vector, indexedAt: Date(),
                metadata: flat
            ))
            documentCount = LocalVectorStore.shared.documentCount
            lastError = nil
            return
        }

        var fullMetadata = metadata
        fullMetadata["type"] = type
        fullMetadata["indexed_at"] = ISO8601DateFormatter().string(from: Date())

        try await apiClient.upsert(id: id, content: content, metadata: fullMetadata)
        lastError = nil
    }

    // MARK: - Delete Document
    func delete(id: String) async throws {
        if isLocal {
            LocalVectorStore.shared.delete(id: id)
            documentCount = LocalVectorStore.shared.documentCount
            lastError = nil
            return
        }
        try await apiClient.delete(id: id)
        lastError = nil
    }

    // MARK: - Search
    func search(query: String, topK: Int = Configuration.RAG.topK, filter: [String: Any]? = nil) async throws -> [SearchResult] {
        if isLocal {
            let queryVector = try EmbeddingService.shared.embedLocally(query)
            let matches = LocalVectorStore.shared.search(
                queryVector: queryVector,
                topK: topK,
                typeFilter: filter?["type"] as? String
            )
            lastError = nil
            return matches.map { match in
                var meta: [String: AnyCodable] = [
                    "type":  AnyCodable(match.type),
                    "title": AnyCodable(match.title)
                ]
                for (key, value) in match.metadata { meta[key] = AnyCodable(value) }
                return SearchResult(
                    id: match.id,
                    score: match.score,
                    metadata: meta,
                    content: match.content
                )
            }
        }

        let results = try await apiClient.search(query: query, topK: topK)

        // Filter by minimum relevance score
        return results.filter { $0.score >= Configuration.RAG.minRelevanceScore }
    }
}
