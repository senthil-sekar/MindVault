//
//  ChatMessage.swift
//  MindVault
//
//  SwiftData models for chat messages and conversations
//

import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var content: String
    var role: String  // "user" or "assistant"
    var timestamp: Date
    var conversationId: UUID
    
    // Context used for RAG
    var contextIds: [String]?  // IDs of retrieved documents
    var contextSnippets: [String]?  // Snippets shown to user
    
    // Feedback
    var isHelpful: Bool?
    var feedback: String?
    
    init(
        id: UUID = UUID(),
        content: String = "",
        role: String = MessageRole.user.rawValue,
        timestamp: Date = Date(),
        conversationId: UUID = UUID(),
        contextIds: [String]? = nil,
        contextSnippets: [String]? = nil,
        isHelpful: Bool? = nil,
        feedback: String? = nil
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.conversationId = conversationId
        self.contextIds = contextIds
        self.contextSnippets = contextSnippets
        self.isHelpful = isHelpful
        self.feedback = feedback
    }
    
    var isUser: Bool {
        role == MessageRole.user.rawValue
    }
    
    var isAssistant: Bool {
        role == MessageRole.assistant.rawValue
    }
}

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var summary: String?
    
    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.summary = summary
    }
}

// MARK: - Message Role
enum MessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

// MARK: - Suggested Questions
struct SuggestedQuestion: Identifiable {
    let id = UUID()
    let question: String
    let category: String
    let icon: String
    
    static let defaults: [SuggestedQuestion] = [
        SuggestedQuestion(
            question: "What are my top skills?",
            category: "Skills",
            icon: "star.fill"
        ),
        SuggestedQuestion(
            question: "Summarize my career journey",
            category: "Career",
            icon: "briefcase.fill"
        ),
        SuggestedQuestion(
            question: "What were my goals this year?",
            category: "Goals",
            icon: "target"
        ),
        SuggestedQuestion(
            question: "What makes me unique?",
            category: "Personal",
            icon: "person.fill"
        ),
        SuggestedQuestion(
            question: "What have I learned recently?",
            category: "Learning",
            icon: "book.fill"
        ),
        SuggestedQuestion(
            question: "What are my happiest memories?",
            category: "Memories",
            icon: "heart.fill"
        ),
        SuggestedQuestion(
            question: "Am I qualified for a senior developer role?",
            category: "Career",
            icon: "checkmark.seal.fill"
        ),
        SuggestedQuestion(
            question: "What patterns do you see in my journal?",
            category: "Insights",
            icon: "chart.line.uptrend.xyaxis"
        )
    ]
}

// MARK: - Chat Context
struct ChatContext: Codable {
    let documentId: String
    let documentType: String  // "journal" or "profile"
    let title: String
    let snippet: String
    let relevanceScore: Float
    let date: Date?
}
