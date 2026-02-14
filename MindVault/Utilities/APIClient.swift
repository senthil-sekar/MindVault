//
//  APIClient.swift
//  MindVault
//
//  Network client for communicating with the backend
//

import Foundation

actor APIClient {
    static let shared = APIClient()
    
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }
    
    // MARK: - Health Check
    func checkHealth() async throws -> HealthResponse {
        let url = try makeURL(Configuration.Endpoints.health)
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try decoder.decode(HealthResponse.self, from: data)
    }
    
    // MARK: - Embedding
    func embed(text: String) async throws -> [Float] {
        let url = try makeURL(Configuration.Endpoints.embedText)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["text": text]
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        let embeddingResponse = try decoder.decode(EmbeddingResponse.self, from: data)
        return embeddingResponse.embedding
    }
    
    // MARK: - Upsert Document
    func upsert(id: String, content: String, metadata: [String: Any]) async throws {
        let url = try makeURL(Configuration.Endpoints.upsert)
        print("📤 APIClient.upsert called - id: \(id), content_len: \(content.count)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let upsertRequest = UpsertRequest(id: id, content: content, metadata: metadata)
        request.httpBody = try encoder.encode(upsertRequest)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
        print("✅ APIClient.upsert succeeded - id: \(id)")
    }
    
    func upsert(request: UpsertRequest) async throws {
        let url = try makeURL(Configuration.Endpoints.upsert)
        print("📤 APIClient.upsert(request) called - id: \(request.id), content_len: \(request.content.count)")
        
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)
        
        let (_, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        print("✅ APIClient.upsert(request) succeeded - id: \(request.id)")

    }
    
    // MARK: - Delete Document
    func delete(id: String) async throws {
        let url = try makeURL(Configuration.Endpoints.delete)
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["id": id]
        request.httpBody = try encoder.encode(body)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }
    
    func delete(request: DeleteRequest) async throws {
        let url = try makeURL(Configuration.Endpoints.delete)
        
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "DELETE"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)
        
        let (_, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
    }
    
    // MARK: - Search
    func search(query: String, topK: Int = Configuration.RAG.topK) async throws -> [SearchResult] {
        let url = try makeURL(Configuration.Endpoints.search)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "query": query,
            "top_k": topK
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        let searchResponse = try decoder.decode(SearchResponse.self, from: data)
        return searchResponse.results
    }
    
    // MARK: - Chat
    func chat(message: String, conversationHistory: [[String: String]]? = nil) async throws -> ChatResponse {
        let url = try makeURL(Configuration.Endpoints.chat)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["message": message]
        if let history = conversationHistory {
            body["history"] = history
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return try decoder.decode(ChatResponse.self, from: data)
    }
    
    func chat(request: ChatRequest) async throws -> ChatResponse {
        let url = try makeURL(Configuration.Endpoints.chat)
        
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
        
        return try decoder.decode(ChatResponse.self, from: data)
    }
    
    
    private func makeURL(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint) else {
            print("❌ Invalid URL: \(endpoint)")
            throw NetworkError.invalidURL
        }
        print("🔗 API Request to: \(endpoint)")
        return url
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(NSError(domain: "Invalid response", code: 0))
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw NetworkError.unauthorized
        case 400...499:
            throw NetworkError.serverError(httpResponse.statusCode)
        case 500...599:
            throw NetworkError.serverError(httpResponse.statusCode)
        default:
            throw NetworkError.unknown(NSError(domain: "HTTP Error", code: httpResponse.statusCode))
        }
    }
}

// MARK: - Batch Operations
extension APIClient {
    func batchUpsert(documents: [(id: String, content: String, metadata: [String: Any])]) async throws {
        for document in documents {
            try await upsert(id: document.id, content: document.content, metadata: document.metadata)
        }
    }
    
    func batchDelete(ids: [String]) async throws {
        for id in ids {
            try await delete(id: id)
        }
    }
}


