//
//  KeychainService.swift
//  MindVault
//
//  Secure credential storage using iOS Keychain
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
    
    private let service = "com.mindvault.app"
    
    private init() {}
    
    // MARK: - Token Storage
    
    func saveToken(_ token: String, for account: String, type: TokenType) throws {
        let key = makeKey(account: account, type: type)
        
        // Check if token already exists
        if let _ = try? retrieveToken(for: account, type: type) {
            // Update existing token
            try updateToken(token, for: key)
        } else {
            // Add new token
            try addToken(token, for: key)
        }
    }
    
    func retrieveToken(for account: String, type: TokenType) throws -> String {
        let key = makeKey(account: account, type: type)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.tokenNotFound
        }
        
        return token
    }
    
    func deleteToken(for account: String, type: TokenType) throws {
        let key = makeKey(account: account, type: type)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed
        }
    }
    
    func deleteAllTokens(for account: String) throws {
        for type in TokenType.allCases {
            try? deleteToken(for: account, type: type)
        }
    }
    
    // MARK: - Private Helpers
    
    private func addToken(_ token: String, for key: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }
    
    private func updateToken(_ token: String, for key: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            throw KeychainError.updateFailed
        }
    }
    
    private func makeKey(account: String, type: TokenType) -> String {
        return "\(account)_\(type.rawValue)"
    }
}

// MARK: - Token Type

enum TokenType: String, CaseIterable {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case idToken = "id_token"
}

// MARK: - Keychain Error

enum KeychainError: LocalizedError {
    case saveFailed
    case updateFailed
    case deleteFailed
    case tokenNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save token to Keychain"
        case .updateFailed:
            return "Failed to update token in Keychain"
        case .deleteFailed:
            return "Failed to delete token from Keychain"
        case .tokenNotFound:
            return "Token not found in Keychain"
        case .invalidData:
            return "Invalid token data"
        }
    }
}
