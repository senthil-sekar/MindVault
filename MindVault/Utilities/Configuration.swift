//
//  Configuration.swift
//  MindVault
//
//  App configuration and constants
//

import Foundation
import Darwin

enum Configuration {
    // MARK: - Server Configuration
    // Auto-detects the Mac's local IP for iOS Simulator.
    // Can be overridden via Settings → AI Backend → Server URL.

    /// Best-guess default: use stored preference, then local IP, then localhost fallback.
    static var defaultServerURL: String {
        if let ip = localIPAddress() {
            return "http://\(ip):8000"
        }
        return "http://localhost:8000"
    }

    static var serverURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? defaultServerURL
    }
    
    static var openAIKey: String {
        UserDefaults.standard.string(forKey: "openAIKey") ?? ""
    }

    // Detect the Mac's Wi-Fi IP address at runtime so the simulator can
    // reach the Docker backend without hardcoding a specific IP.
    private static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
            ptr = ptr!.pointee.ifa_next
        }
        return address
    }
    
    // MARK: - API Endpoints
    enum Endpoints {
        static var embedText: String { "\(serverURL)/api/embed" }
        static var search: String { "\(serverURL)/api/search" }
        static var chat: String { "\(serverURL)/api/chat" }
        static var health: String { "\(serverURL)/health" }
        static var upsert: String { "\(serverURL)/api/upsert" }
        static var upsertEmail: String { "\(serverURL)/api/upsert/email" }
        static var upsertDocument: String { "\(serverURL)/api/upsert/document" }
        static var delete: String { "\(serverURL)/api/delete" }
    }
    
    // MARK: - RAG Configuration
    enum RAG {
        static let topK = 5  // Number of documents to retrieve
        static let minRelevanceScore: Float = 0.1  // Very low to catch generic queries
        static let maxContextTokens = 4000
        static let embeddingModel = "text-embedding-3-small"
        static let embeddingDimension = 1536
    }
    
    // MARK: - LLM Configuration
    enum LLM {
        static let model = "gpt-4-turbo-preview"
        static let maxTokens = 2000
        static let temperature = 0.7
        
        static let systemPrompt = """
        You are a personal AI assistant for MindVault, a personal journal app. You have access to the user's journal entries, skills, education, work experience, and personal information through the provided context.

        Your role is to:
        1. Answer questions about the user's life, experiences, and capabilities
        2. Help them reflect on their journey and growth
        3. Provide insights based on their recorded information
        4. Act as a knowledgeable assistant who truly understands them

        Guidelines:
        - Be warm, supportive, and encouraging
        - Base your responses on the provided context
        - If you don't have enough context to answer, say so honestly
        - Help the user discover patterns and insights in their life
        - Respect the user's privacy and be thoughtful about sensitive topics
        - When discussing skills or qualifications, be accurate about proficiency levels
        - Use specific examples from their journal when relevant
        
        Remember: You're not just an AI - you're their personal assistant who has learned about them through their journal.
        """
    }
    
    // MARK: - Storage Keys
    enum StorageKeys {
        static let isOnboarded = "isOnboarded"
        static let serverURL = "serverURL"
        static let openAIKey = "openAIKey"
        static let autoSync = "autoSync"
        static let lastSyncDate = "lastSyncDate"
    }
}

// MARK: - Network Errors
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case serverError(Int)
    case connectionError
    case unauthorized
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .noData:
            return "No data received from server"
        case .decodingError:
            return "Failed to decode server response"
        case .serverError(let code):
            return "Server error (code: \(code))"
        case .connectionError:
            return "Unable to connect to server"
        case .unauthorized:
            return "Unauthorized - check your API key"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - API Response Types
struct EmbeddingResponse: Codable {
    let embedding: [Float]
    let id: String?
}

struct SearchResponse: Codable {
    let results: [SearchResult]
}

struct SearchResult: Codable {
    let id: String
    let score: Float
    let metadata: [String: AnyCodable]
    let content: String?
}

struct ChatResponse: Codable {
    let response: String
    let contexts: [ContextResult]
}

struct ContextResult: Codable {
    let id: String
    let type: String
    let title: String
    let snippet: String
    let score: Float
}

struct UpsertRequest: Codable {
    let id: String
    let content: String
    let metadata: [String: AnyCodable]
    
    init(id: String, content: String, metadata: [String: Any]) {
        self.id = id
        self.content = content
        self.metadata = metadata.mapValues { AnyCodable($0) }
    }
}

struct DeleteRequest: Codable {
    let id: String
}

struct ChatRequest: Codable {
    let message: String
    let history: [[String: String]]?
    
    init(message: String, history: [[String: String]]? = nil) {
        self.message = message
        self.history = history
    }
}

struct HealthResponse: Codable {
    let status: String
    let vectorDbStatus: String
    let embeddingsReady: Bool
}

// MARK: - AnyCodable for flexible JSON handling
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
