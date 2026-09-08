//
//  Configuration.swift
//  MindVault
//
//  App configuration and constants
//

import Foundation

enum Configuration {
    // MARK: - Google OAuth
    /// Supplied by `Config.xcconfig` (see `Config.local.xcconfig.example`) and surfaced through
    /// Info.plist. iOS OAuth clients have no client secret — the flow is PKCE — so the client ID
    /// is a public identifier, but it stays out of source so each developer can point the app at
    /// their own Google Cloud project.
    enum GoogleOAuth {
        /// Empty when unconfigured, e.g. `123-abc.apps.googleusercontent.com`.
        static let clientID: String = {
            let value = Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? ""
            return value.hasPrefix(".") ? "" : value
        }()

        /// Reversed client ID, e.g. `com.googleusercontent.apps.123-abc`.
        static var reversedClientID: String {
            guard !clientID.isEmpty else { return "" }
            return "com.googleusercontent.apps." + clientID.replacingOccurrences(
                of: ".apps.googleusercontent.com", with: ""
            )
        }

        /// Gmail uses the bundle-ID scheme, Drive the reversed-client-ID scheme.
        /// Both are registered in Info.plist.
        static let appURLScheme = "com.mindvault.app"
        static let appRedirectURI = "com.mindvault.app:/oauth2redirect"
        static var driveRedirectURI: String { "\(reversedClientID):/oauth2redirect" }
    }

    // MARK: - LLM Provider Mode

    /// Defaults to On-Device: the privacy-first choice, and the one that needs
    /// no setup (no API key to enter) the first time the app runs.
    static var llmMode: LLMProviderMode {
        let raw = UserDefaults.standard.string(forKey: "llmMode") ?? LLMProviderMode.localLLM.rawValue
        return LLMProviderMode(rawValue: raw) ?? .localLLM
    }

    // MARK: - BYOK / Local Model Settings

    enum BYOK {
        static var openAIModel: String {
            UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4o-mini"
        }
        static var localModelPath: String {
            UserDefaults.standard.string(forKey: "localModelPath") ?? ""
        }
    }

    // MARK: - RAG Configuration
    enum RAG {
        static let topK = 5
        static let minRelevanceScore: Float = 0.1
    }

    // MARK: - LLM Configuration
    enum LLM {
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
}

// MARK: - Search Result Types

struct SearchResult: Codable {
    let id: String
    let score: Float
    let metadata: [String: AnyCodable]
    let content: String?
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
