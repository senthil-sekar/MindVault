//
//  ProfileItem.swift
//  MindVault
//
//  SwiftData model for profile items (skills, education, experience)
//

import Foundation
import SwiftData

@Model
final class ProfileItem {
    var id: UUID
    var type: String
    var title: String
    var subtitle: String?
    var content: String
    var startDate: Date?
    var endDate: Date?
    var isCurrent: Bool
    var tags: [String]
    var proficiencyLevel: Int?  // 1-5 for skills
    var createdAt: Date
    var updatedAt: Date
    var embeddingId: String?
    var isEmbedded: Bool
    
    // Additional metadata stored as JSON string
    var metadataJSON: String?
    
    init(
        id: UUID = UUID(),
        type: String = ProfileType.skill.rawValue,
        title: String = "",
        subtitle: String? = nil,
        content: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        isCurrent: Bool = false,
        tags: [String] = [],
        proficiencyLevel: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        embeddingId: String? = nil,
        isEmbedded: Bool = false,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.startDate = startDate
        self.endDate = endDate
        self.isCurrent = isCurrent
        self.tags = tags
        self.proficiencyLevel = proficiencyLevel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.embeddingId = embeddingId
        self.isEmbedded = isEmbedded
        self.metadataJSON = metadataJSON
    }
    
    // Full text for embeddings
    var fullText: String {
        var text = "\(type): \(title)"
        if let subtitle = subtitle {
            text += " at \(subtitle)"
        }
        text += "\n\n\(content)"
        if !tags.isEmpty {
            text += "\n\nSkills/Keywords: \(tags.joined(separator: ", "))"
        }
        if let level = proficiencyLevel {
            text += "\nProficiency Level: \(level)/5"
        }
        if let start = startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            text += "\nPeriod: \(formatter.string(from: start))"
            if let end = endDate {
                text += " - \(formatter.string(from: end))"
            } else if isCurrent {
                text += " - Present"
            }
        }
        return text
    }
    
    // Metadata for vector DB
    var metadata: [String: Any] {
        return [
            "id": id.uuidString,
            "type": type,
            "title": title,
            "proficiency": proficiencyLevel ?? 0,
            "tags": tags,
            "is_current": isCurrent
        ]
    }
    
    // Duration in years
    var durationYears: Double? {
        guard let start = startDate else { return nil }
        let end = endDate ?? Date()
        let components = Calendar.current.dateComponents([.day], from: start, to: end)
        return Double(components.day ?? 0) / 365.0
    }
}

// MARK: - Profile Type Enum
enum ProfileType: String, CaseIterable, Codable {
    case skill = "Skill"
    case education = "Education"
    case experience = "Experience"
    case certification = "Certification"
    case project = "Project"
    case achievement = "Achievement"
    case language = "Language"
    case interest = "Interest"
    case value = "Value"
    
    var icon: String {
        switch self {
        case .skill: return "star.fill"
        case .education: return "graduationcap.fill"
        case .experience: return "briefcase.fill"
        case .certification: return "checkmark.seal.fill"
        case .project: return "folder.fill"
        case .achievement: return "trophy.fill"
        case .language: return "globe"
        case .interest: return "heart.fill"
        case .value: return "sparkles"
        }
    }
    
    var color: String {
        switch self {
        case .skill: return "yellow"
        case .education: return "purple"
        case .experience: return "blue"
        case .certification: return "green"
        case .project: return "orange"
        case .achievement: return "pink"
        case .language: return "teal"
        case .interest: return "red"
        case .value: return "indigo"
        }
    }
}
