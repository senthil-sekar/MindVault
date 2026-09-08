//
//  EmailAccount.swift
//  MindVault
//
//  Created with AI assistance
//

import Foundation
import SwiftData

@Model
final class EmailAccount {
    var id: UUID
    var email: String
    var provider: EmailProvider
    var displayName: String
    var isConnected: Bool
    var lastSyncDate: Date?
    var tokenExpiryDate: Date?
    var createdAt: Date
    var updatedAt: Date
    
    // Note: Tokens are stored securely in Keychain, not in the database
    // Use KeychainService to retrieve tokens
    
    @Relationship(deleteRule: .cascade, inverse: \EmailMessage.account)
    var messages: [EmailMessage]?
    
    init(
        id: UUID = UUID(),
        email: String,
        provider: EmailProvider,
        displayName: String,
        isConnected: Bool = false,
        lastSyncDate: Date? = nil,
        tokenExpiryDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.provider = provider
        self.displayName = displayName
        self.isConnected = isConnected
        self.lastSyncDate = lastSyncDate
        self.tokenExpiryDate = tokenExpiryDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Token Management
    
    func saveTokens(accessToken: String, refreshToken: String?, idToken: String?) throws {
        let keychain = KeychainService.shared
        
        try keychain.saveToken(accessToken, for: email, type: .accessToken)
        
        if let refreshToken = refreshToken {
            try keychain.saveToken(refreshToken, for: email, type: .refreshToken)
        }
        
        if let idToken = idToken {
            try keychain.saveToken(idToken, for: email, type: .idToken)
        }
    }
    
    func getAccessToken() throws -> String {
        return try KeychainService.shared.retrieveToken(for: email, type: .accessToken)
    }
    
    func getRefreshToken() throws -> String {
        return try KeychainService.shared.retrieveToken(for: email, type: .refreshToken)
    }
    
    func deleteTokens() throws {
        try KeychainService.shared.deleteAllTokens(for: email)
    }
}

enum EmailProvider: String, Codable, CaseIterable {
    case gmail = "Gmail"
    case outlook = "Outlook"
    case icloud = "iCloud"
    case other = "Other"
    
    var iconName: String {
        switch self {
        case .gmail: return "envelope.circle.fill"
        case .outlook: return "envelope.circle.fill"
        case .icloud: return "envelope.circle.fill"
        case .other: return "envelope.circle"
        }
    }
    
    var color: String {
        switch self {
        case .gmail: return "red"
        case .outlook: return "blue"
        case .icloud: return "blue"
        case .other: return "gray"
        }
    }
}
