//
//  DriveDocument.swift
//  MindVault
//
//  Model for Google Drive documents
//

import Foundation
import SwiftData

@Model
final class DriveDocument {
    var id: UUID
    var fileId: String  // Google Drive file ID
    var name: String
    var mimeType: String
    var size: Int64
    var modifiedTime: Date
    var folderPath: String?
    var webViewLink: String?
    
    // Processing status
    var isProcessedForAI: Bool
    var processedAt: Date?
    var chunksCount: Int
    var lastError: String?
    
    // Parent folder info
    var parentFolderId: String?
    var parentFolderName: String?
    
    init(
        id: UUID = UUID(),
        fileId: String,
        name: String,
        mimeType: String,
        size: Int64 = 0,
        modifiedTime: Date = Date(),
        folderPath: String? = nil,
        webViewLink: String? = nil,
        isProcessedForAI: Bool = false,
        processedAt: Date? = nil,
        chunksCount: Int = 0,
        lastError: String? = nil,
        parentFolderId: String? = nil,
        parentFolderName: String? = nil
    ) {
        self.id = id
        self.fileId = fileId
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.modifiedTime = modifiedTime
        self.folderPath = folderPath
        self.webViewLink = webViewLink
        self.isProcessedForAI = isProcessedForAI
        self.processedAt = processedAt
        self.chunksCount = chunksCount
        self.lastError = lastError
        self.parentFolderId = parentFolderId
        self.parentFolderName = parentFolderName
    }
    
    // MARK: - Computed Properties
    
    var displayType: String {
        switch mimeType {
        case "application/pdf":
            return "PDF"
        case "application/vnd.google-apps.document":
            return "Google Doc"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            return "Word Doc"
        case "application/vnd.google-apps.spreadsheet":
            return "Google Sheet"
        case "text/plain":
            return "Text File"
        case "text/markdown":
            return "Markdown"
        default:
            return "Document"
        }
    }
    
    var iconName: String {
        switch mimeType {
        case "application/pdf":
            return "doc.fill"
        case "application/vnd.google-apps.document", 
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            return "doc.text.fill"
        case "application/vnd.google-apps.spreadsheet":
            return "tablecells.fill"
        case "text/plain", "text/markdown":
            return "doc.plaintext.fill"
        case "application/vnd.google-apps.folder":
            return "folder.fill"
        default:
            return "doc"
        }
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var isFolder: Bool {
        mimeType == "application/vnd.google-apps.folder"
    }
    
    var isSupported: Bool {
        let supportedTypes = [
            "application/pdf",
            "application/vnd.google-apps.document",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "text/plain",
            "text/markdown"
        ]
        return supportedTypes.contains(mimeType)
    }
}

// MARK: - Drive Folder (for navigation)

struct DriveFolder: Identifiable, Hashable {
    let id: String
    let name: String
    let parentId: String?
    
    static let root = DriveFolder(id: "root", name: "My Drive", parentId: nil)
}
