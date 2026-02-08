//
//  JournalEntry.swift
//  MindVault
//
//  SwiftData model for journal entries
//

import Foundation
import SwiftData

@Model
final class JournalEntry {
    var id: UUID
    var title: String
    var content: String
    var category: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var embeddingId: String?
    var isEmbedded: Bool
    
    // Mood tracking (optional)
    var mood: String?
    var moodScore: Int?
    
    // Location (optional)
    var locationName: String?
    
    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        category: String = Category.personal.rawValue,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        embeddingId: String? = nil,
        isEmbedded: Bool = false,
        mood: String? = nil,
        moodScore: Int? = nil,
        locationName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.embeddingId = embeddingId
        self.isEmbedded = isEmbedded
        self.mood = mood
        self.moodScore = moodScore
        self.locationName = locationName
    }
    
    // Computed property for full text (used for embeddings)
    var fullText: String {
        var text = "\(title)\n\n\(content)"
        if !tags.isEmpty {
            text += "\n\nTags: \(tags.joined(separator: ", "))"
        }
        if let mood = mood {
            text += "\nMood: \(mood)"
        }
        return text
    }
    
    // Metadata for vector DB
    var metadata: [String: Any] {
        return [
            "id": id.uuidString,
            "type": "journal_entry",
            "category": category,
            "tags": tags,
            "created_at": createdAt.ISO8601Format(),
            "title": title
        ]
    }
}

// MARK: - Category Enum
enum Category: String, CaseIterable, Codable {
    case personal = "Personal"
    case work = "Work"
    case education = "Education"
    case skills = "Skills"
    case memories = "Memories"
    case goals = "Goals"
    case health = "Health"
    case relationships = "Relationships"
    case travel = "Travel"
    case creativity = "Creativity"
    case finance = "Finance"
    case reflection = "Reflection"
    
    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .work: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .skills: return "star.fill"
        case .memories: return "photo.fill"
        case .goals: return "target"
        case .health: return "heart.fill"
        case .relationships: return "person.2.fill"
        case .travel: return "airplane"
        case .creativity: return "paintbrush.fill"
        case .finance: return "dollarsign.circle.fill"
        case .reflection: return "thought.bubble.fill"
        }
    }
    
    var color: String {
        switch self {
        case .personal: return "indigo"
        case .work: return "blue"
        case .education: return "purple"
        case .skills: return "yellow"
        case .memories: return "pink"
        case .goals: return "green"
        case .health: return "red"
        case .relationships: return "orange"
        case .travel: return "teal"
        case .creativity: return "mint"
        case .finance: return "cyan"
        case .reflection: return "gray"
        }
    }
}

// MARK: - Mood Enum
enum Mood: String, CaseIterable {
    case amazing = "Amazing"
    case happy = "Happy"
    case good = "Good"
    case okay = "Okay"
    case meh = "Meh"
    case sad = "Sad"
    case stressed = "Stressed"
    case anxious = "Anxious"
    case angry = "Angry"
    
    var emoji: String {
        switch self {
        case .amazing: return "🤩"
        case .happy: return "😊"
        case .good: return "🙂"
        case .okay: return "😐"
        case .meh: return "😕"
        case .sad: return "😢"
        case .stressed: return "😰"
        case .anxious: return "😟"
        case .angry: return "😠"
        }
    }
    
    var score: Int {
        switch self {
        case .amazing: return 5
        case .happy: return 4
        case .good: return 4
        case .okay: return 3
        case .meh: return 2
        case .sad: return 1
        case .stressed: return 2
        case .anxious: return 2
        case .angry: return 1
        }
    }
}
