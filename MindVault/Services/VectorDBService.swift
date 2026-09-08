//
//  VectorDBService.swift
//  MindVault
//
//  Thin wrapper around LocalVectorStore: handles embedding text before storage,
//  flattening caller metadata, and shaping search results as SearchResult.
//

import Foundation

@MainActor
class VectorDBService: ObservableObject {
    static let shared = VectorDBService()

    @Published var lastError: String?

    private init() {}

    // MARK: - Upsert Document
    func upsert(id: String, content: String, type: String, metadata: [String: Any]) async throws {
        let title = (metadata["title"] as? String)
            ?? (metadata["subject"] as? String)
            ?? type
        let vector = try EmbeddingService.embedLocally(content)
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
        lastError = nil
    }

    // MARK: - Delete Document
    func delete(id: String) async throws {
        LocalVectorStore.shared.delete(id: id)
        lastError = nil
    }

    // MARK: - Search
    func search(query: String, topK: Int = Configuration.RAG.topK, filter: [String: Any]? = nil) async throws -> [SearchResult] {
        let queryVector = try EmbeddingService.embedLocally(query)
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
}
