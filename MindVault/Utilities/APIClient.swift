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

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let upsertRequest = UpsertRequest(id: id, content: content, metadata: metadata)
        request.httpBody = try encoder.encode(upsertRequest)

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func upsert(request: UpsertRequest) async throws {
        let url = try makeURL(Configuration.Endpoints.upsert)

        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try encoder.encode(request)

        let (_, response) = try await session.data(for: httpRequest)
        try validateResponse(response)
    }
    
    // MARK: - Upsert Email (Improved Processing)
    
    /// Upsert an email with improved processing (cleaning, chunking, hybrid search metadata)
    func upsertEmail(
        id: String,
        content: String,
        subject: String,
        sender: String,
        date: Date,
        threadId: String? = nil,
        labels: [String]? = nil
    ) async throws {
        let url = try makeURL(Configuration.Endpoints.upsertEmail)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        var body: [String: Any] = [
            "id": id,
            "content": content,
            "subject": subject,
            "sender": sender,
            "date": ISO8601DateFormatter().string(from: date)
        ]
        
        if let threadId = threadId {
            body["thread_id"] = threadId
        }
        
        if let labels = labels {
            body["labels"] = labels
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
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
            throw NetworkError.invalidURL
        }
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
