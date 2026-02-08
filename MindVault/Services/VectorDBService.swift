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
    
    // MARK: - Connection Check
    func checkConnection() async {
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
        var fullMetadata = metadata
        fullMetadata["type"] = type
        fullMetadata["indexed_at"] = ISO8601DateFormatter().string(from: Date())
        
        try await apiClient.upsert(id: id, content: content, metadata: fullMetadata)
        lastError = nil
    }
    
    // MARK: - Delete Document
    func delete(id: String) async throws {
        try await apiClient.delete(id: id)
        lastError = nil
    }
    
    // MARK: - Search
    func search(query: String, topK: Int = Configuration.RAG.topK, filter: [String: Any]? = nil) async throws -> [SearchResult] {
        let results = try await apiClient.search(query: query, topK: topK)
        
        // Filter by minimum relevance score
        return results.filter { $0.score >= Configuration.RAG.minRelevanceScore }
    }
    
    // MARK: - Batch Operations
    func batchUpsert(documents: [(id: String, content: String, type: String, metadata: [String: Any])]) async throws {
        for doc in documents {
            try await upsert(id: doc.id, content: doc.content, type: doc.type, metadata: doc.metadata)
        }
    }
    
    func batchDelete(ids: [String]) async throws {
        for id in ids {
            try await delete(id: id)
        }
    }
}

// MARK: - Document Types
extension VectorDBService {
    enum DocumentType: String {
        case journalEntry = "journal_entry"
        case profileItem = "profile_item"
    }
}
