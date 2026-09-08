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
        /// Source-specific fields (thread_id, file_id, chunk, from, date…).
        /// Stringified so the store stays plain Codable.
        var metadata: [String: String] = [:]

        // Explicit decoder so stores written before `metadata` existed still load.
        init(id: String, type: String, title: String, content: String,
             vector: [Float], indexedAt: Date, metadata: [String: String] = [:]) {
            self.id = id
            self.type = type
            self.title = title
            self.content = content
            self.vector = vector
            self.indexedAt = indexedAt
            self.metadata = metadata
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            type = try c.decode(String.self, forKey: .type)
            title = try c.decode(String.self, forKey: .title)
            content = try c.decode(String.self, forKey: .content)
            vector = try c.decode([Float].self, forKey: .vector)
            indexedAt = try c.decode(Date.self, forKey: .indexedAt)
            metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        }
    }

    @Published private(set) var documentCount: Int = 0

    private var documents: [String: VectorDocument] = [:]
    private let storageURL: URL
    private var pendingSave: Task<Void, Never>?

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

    /// Removes every document whose id starts with `prefix`. Used to clear the
    /// old chunks of a re-indexed document, which would otherwise linger when
    /// the new version has fewer chunks than the old one.
    func deleteAll(withPrefix prefix: String) {
        let doomed = documents.keys.filter { $0.hasPrefix(prefix) }
        guard !doomed.isEmpty else { return }
        for key in doomed { documents.removeValue(forKey: key) }
        documentCount = documents.count
        persistAsync()
    }

    // MARK: - Search

    struct SearchMatch {
        let id: String
        let type: String
        let title: String
        let content: String
        let score: Float
        let metadata: [String: String]
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
                    score: cosineSimilarity(queryVector, doc.vector),
                    metadata: doc.metadata
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

    /// Coalesces bursts of upserts into a single write.
    ///
    /// Indexing a Drive document or an email sync fires one upsert per chunk;
    /// writing the whole store each time is O(n²) in bytes. Worse, unordered
    /// concurrent writes let an older snapshot land after a newer one and
    /// silently drop documents. Cancelling the pending task keeps writes
    /// serialized and always persists the latest state.
    private func persistAsync() {
        pendingSave?.cancel()
        let docs = Array(documents.values)
        let url = storageURL
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await Self.write(docs, to: url)
            self?.pendingSave = nil
        }
    }

    /// Write the store immediately, bypassing the debounce. Call before the app
    /// backgrounds so an in-flight coalesce window can't lose the last change.
    func flush() async {
        pendingSave?.cancel()
        pendingSave = nil
        await Self.write(Array(documents.values), to: storageURL)
    }

    private nonisolated static func write(_ docs: [VectorDocument], to url: URL) async {
        if let data = try? JSONEncoder().encode(docs) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Cosine Similarity (Accelerate)

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        // Never compare across dimensions. Truncating to the shorter vector
        // yields plausible-looking but meaningless scores if the store ever
        // mixes embeddings from different models (e.g. 512-dim NLEmbedding
        // alongside the backend's 384-dim all-MiniLM-L6-v2).
        guard a.count == b.count else { return 0 }
        let n = vDSP_Length(a.count)
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
