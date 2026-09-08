//
//  LocalVectorStore.swift
//  MindVault
//
//  On-device vector store: JSON-persisted documents with vDSP cosine similarity search.
//  Used when llmMode == .localLLM to avoid any backend calls.
//

import Foundation
import Accelerate

@MainActor
final class LocalVectorStore: ObservableObject {
    static let shared = LocalVectorStore()

    struct VectorDocument: Codable, Sendable {
        let id: String
        let type: String
        let title: String
        let content: String      // full text for context snippets
        let vector: [Float]
        let indexedAt: Date
    }

    @Published private(set) var documentCount: Int = 0

    private var documents: [String: VectorDocument] = [:]
    private let storageURL: URL

    private init() {
        storageURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mindvault_vectors.json")
        loadFromDisk()
    }

    // MARK: - CRUD

    func upsert(_ doc: VectorDocument) {
        documents[doc.id] = doc
        documentCount = documents.count
        persistAsync()
    }

    func delete(id: String) {
        documents.removeValue(forKey: id)
        documentCount = documents.count
        persistAsync()
    }

    func deleteAll() {
        documents.removeAll()
        documentCount = 0
        persistAsync()
    }

    // MARK: - Search

    struct SearchMatch {
        let id: String
        let type: String
        let title: String
        let content: String
        let score: Float
    }

    func search(queryVector: [Float], topK: Int, typeFilter: String? = nil) -> [SearchMatch] {
        let candidates = typeFilter.map { t in documents.values.filter { $0.type == t } }
            ?? Array(documents.values)

        return candidates
            .map { doc in
                SearchMatch(
                    id: doc.id,
                    type: doc.type,
                    title: doc.title,
                    content: doc.content,
                    score: cosineSimilarity(queryVector, doc.vector)
                )
            }
            .filter { $0.score >= Configuration.RAG.minRelevanceScore }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let docs = try? JSONDecoder().decode([VectorDocument].self, from: data) else { return }
        documents = Dictionary(uniqueKeysWithValues: docs.map { ($0.id, $0) })
        documentCount = documents.count
    }

    private func persistAsync() {
        let docs = Array(documents.values)
        let url = storageURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(docs) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Cosine Similarity (Accelerate)

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let n = vDSP_Length(min(a.count, b.count))
        guard n > 0 else { return 0 }
        var dot: Float = 0
        var sumSqA: Float = 0
        var sumSqB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, n)
        vDSP_svesq(a, 1, &sumSqA, n)
        vDSP_svesq(b, 1, &sumSqB, n)
        let denom = sqrt(sumSqA) * sqrt(sumSqB)
        guard denom > 1e-8 else { return 0 }
        return dot / denom
    }
}
