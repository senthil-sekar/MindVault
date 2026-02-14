//
//  EmailService.swift
//  MindVault
//
//  Created with AI assistance
//

import Foundation
import SwiftUI
import AuthenticationServices
import SwiftData
import CommonCrypto

@MainActor
class EmailService: NSObject, ObservableObject {
    @Published var isConnecting: Bool = false
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
    @Published var lastError: String?
    
    private let modelContext: ModelContext
    private var authSession: ASWebAuthenticationSession?
    private var codeVerifier: String?
    
    // Gmail OAuth Configuration
    // TODO: Replace with your actual Gmail Client ID from Google Cloud Console
    // Get it from: https://console.cloud.google.com/apis/credentials
    // 1. Create project 2. Enable Gmail API 3. Create OAuth Client ID (iOS)
    private let gmailClientId = "139218014357-3viojsk9bvbrqo96lbesscifdj0itdlf.apps.googleusercontent.com"
    private let gmailRedirectURI = "com.mindvault.app:/oauth2redirect"
    private let gmailAuthURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let gmailTokenURL = "https://oauth2.googleapis.com/token"
    private let gmailScope = "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/userinfo.email openid"
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
    }
    
    // MARK: - Configuration Validation
    
    func isConfigured() -> Bool {
        return !gmailClientId.isEmpty && gmailClientId.contains("apps.googleusercontent.com")
    }
    
    // MARK: - OAuth Authentication with PKCE
    
    func connectGmailAccount(presentationAnchor: ASPresentationAnchor) async throws -> EmailAccount {
        isConnecting = true
        lastError = nil
        
        defer { isConnecting = false }
        
        do {
            // Generate PKCE code verifier and challenge
            let (verifier, challenge) = generatePKCEPair()
            self.codeVerifier = verifier
            
            // Step 1: Get authorization code with PKCE
            let authCode = try await getAuthorizationCode(
                presentationAnchor: presentationAnchor,
                codeChallenge: challenge
            )
            
            // Step 2: Exchange auth code for tokens
            let tokens = try await exchangeCodeForTokens(authCode: authCode, codeVerifier: verifier)
            
            // Step 3: Get user email from ID token or userinfo endpoint
            let userEmail = try await getUserEmail(accessToken: tokens.accessToken, idToken: tokens.idToken)
            
            // Step 4: Create and save account
            let account = EmailAccount(
                email: userEmail,
                provider: .gmail,
                displayName: userEmail,
                isConnected: true,
                tokenExpiryDate: Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
            )
            
            // Step 5: Save tokens securely in Keychain
            try account.saveTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                idToken: tokens.idToken
            )
            
            modelContext.insert(account)
            try modelContext.save()
            
            return account
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - PKCE Implementation
    
    private func generatePKCEPair() -> (verifier: String, challenge: String) {
        // Generate code verifier (43-128 characters)
        let verifier = generateRandomString(length: 128)
        
        // Generate code challenge (SHA256 hash of verifier, base64url encoded)
        let challenge = sha256(verifier).base64URLEncoded()
        
        return (verifier, challenge)
    }
    
    private func generateRandomString(length: Int) -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    private func sha256(_ string: String) -> Data {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    private func getAuthorizationCode(presentationAnchor: ASPresentationAnchor, codeChallenge: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let state = UUID().uuidString
            
            var components = URLComponents(string: gmailAuthURL)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: gmailClientId),
                URLQueryItem(name: "redirect_uri", value: gmailRedirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: gmailScope),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]
            
            guard let authURL = components.url else {
                continuation.resume(throwing: EmailServiceError.invalidURL)
                return
            }
            
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.mindvault.app"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: EmailServiceError.authorizationFailed)
                    return
                }
                
                continuation.resume(returning: code)
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
            
            self.authSession = session
        }
    }
    
    private func exchangeCodeForTokens(authCode: String, codeVerifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: gmailTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "code": authCode,
            "client_id": gmailClientId,
            "redirect_uri": gmailRedirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EmailServiceError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse
    }
    
    private func getUserEmail(accessToken: String, idToken: String?) async throws -> String {
        // Try to get email from ID token first (OpenID Connect)
        if let idToken = idToken, let email = decodeEmailFromIDToken(idToken) {
            return email
        }
        
        // Fallback to userinfo endpoint
        let url = URL(string: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EmailServiceError.userInfoFailed
        }
        
        let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
        return userInfo.email
    }
    
    private func decodeEmailFromIDToken(_ idToken: String) -> String? {
        // ID token is a JWT with format: header.payload.signature
        let segments = idToken.components(separatedBy: ".")
        guard segments.count == 3 else { return nil }
        
        // Decode the payload (second segment)
        var payload = segments[1]
        
        // Add padding if needed for base64 decoding
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return nil
        }
        
        return email
    }
    
    // MARK: - Email Syncing
    
    /// Process existing emails that are already in the local database and send them to the backend
    func processExistingEmails(for account: EmailAccount, limit: Int? = nil) async throws {
        print("🔄 Processing existing emails for AI indexing...")
        
        isSyncing = true
        syncProgress = 0.0
        lastError = nil
        defer { isSyncing = false }
        
        // Fetch all emails from database for this account
        let descriptor = FetchDescriptor<EmailMessage>()
        let allEmails = try modelContext.fetch(descriptor)
        
        // Filter for this account's emails that aren't processed yet
        var emails = allEmails.filter { email in
            email.account?.id == account.id && !email.isProcessedForAI
        }
        
        // Limit if specified
        if let limit = limit {
            emails = Array(emails.prefix(limit))
        }
        
        print("📧 Found \(emails.count) unprocessed emails to index")
        
        guard !emails.isEmpty else {
            print("✅ All emails already processed!")
            return
        }
        
        let apiClient = APIClient.shared
        
        for (index, emailMessage) in emails.enumerated() {
            print("💾 Processing email \(index + 1)/\(emails.count): \(emailMessage.subject)")
            
            // Create content for embedding
            let content = """
            From: \(emailMessage.from)
            Subject: \(emailMessage.subject)
            Date: \(DateFormatter().string(from: emailMessage.date))
            
            \(emailMessage.body)
            """
            
            // Metadata for filtering
            var metadata: [String: Any] = [
                "type": "email",
                "from": emailMessage.from,
                "subject": emailMessage.subject,
                "date": ISO8601DateFormatter().string(from: emailMessage.date)
            ]
            
            if let threadId = emailMessage.threadId, !threadId.isEmpty {
                metadata["thread_id"] = threadId
            }
            
            // Send to backend
            do {
                print("  → Sending to backend: \(emailMessage.subject)")
                try await apiClient.upsert(id: emailMessage.id.uuidString, content: content, metadata: metadata)
                print("✅ Email indexed: \(emailMessage.subject)")
                emailMessage.isProcessedForAI = true
                try modelContext.save()
            } catch {
                print("❌ Failed to index email \(emailMessage.subject): \(error.localizedDescription)")
            }
            
            syncProgress = Double(index + 1) / Double(emails.count)
        }
        
        print("✨ Finished processing \(emails.count) emails")
    }
    
    func syncEmails(for account: EmailAccount, limit: Int = 50) async throws {
        guard account.isConnected else {
            throw EmailServiceError.accountNotConnected
        }
        
        isSyncing = true
        syncProgress = 0.0
        lastError = nil
        
        defer { isSyncing = false }
        
        do {
            // Refresh token if needed
            if let expiryDate = account.tokenExpiryDate, expiryDate < Date() {
                try await refreshAccessToken(for: account)
            }
            
            // Get access token from Keychain
            let accessToken = try account.getAccessToken()
            
            // Fetch messages
            let messages = try await fetchMessages(accessToken: accessToken, limit: limit)
            print("📨 Fetched \(messages.count) messages from Gmail")
            
            syncProgress = 0.5
            
            // Save messages to database and process for RAG
            for (index, message) in messages.enumerated() {
                print("💾 Saving message \(index + 1)/\(messages.count): \(message.subject)")
                let emailMessage = EmailMessage(
                    messageId: message.id,
                    threadId: message.threadId,
                    subject: message.subject,
                    from: message.from,
                    fromName: message.fromName,
                    to: message.to,
                    body: message.body,
                    bodySnippet: message.snippet,
                    isHTML: message.isHTML,
                    date: message.date,
                    isRead: message.isRead,
                    labels: message.labels,
                    hasAttachments: message.hasAttachments
                )
                emailMessage.account = account
                
                modelContext.insert(emailMessage)
                try modelContext.save()
                
                // Process this email immediately for RAG
                do {
                    print("  → Sending to backend: \(message.subject)")
                    let apiClient = APIClient.shared
                    
                    // Content: Full email text that will be embedded
                    let content = """
                    From: \(message.from)
                    Subject: \(message.subject)
                    Date: \(DateFormatter().string(from: message.date))
                    
                    \(message.body)
                    """
                    
                    // Metadata: Searchable/filterable fields only (NOT the content!)
                    var metadata: [String: Any] = [
                        "type": "email",
                        "from": message.from,
                        "subject": message.subject,
                        "date": ISO8601DateFormatter().string(from: message.date)
                    ]
                    
                    if !message.threadId.isEmpty {
                        metadata["thread_id"] = message.threadId
                    }
                    
                    print("  📤 Upsert details - Content length: \(content.count), Metadata keys: \(metadata.keys.joined(separator: ", "))")
                    
                    try await apiClient.upsert(id: emailMessage.id.uuidString, content: content, metadata: metadata)
                    print("✅ Email indexed: \(message.subject)")
                    emailMessage.isProcessedForAI = true
                    try modelContext.save()
                } catch {
                    print("❌ Failed to index email \(message.subject): \(error.localizedDescription)")
                }
                
                syncProgress = 0.5 + (Double(index + 1) / Double(messages.count)) * 0.5
            }
            
            account.lastSyncDate = Date()
            account.updatedAt = Date()
            try modelContext.save()
            
            syncProgress = 0.9
            print("✨ All emails synced and indexed")
            syncProgress = 1.0
        } catch {
            print("❌ Email sync failed: \(error)")
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - RAG Processing
    
    private func processEmailsForRAG(messages: [GmailMessage]) async {
        // Process emails for RAG context and send to backend
        let apiClient = APIClient.shared
        print("🔄 Starting to process \(messages.count) emails for RAG...")
        
        for (index, message) in messages.enumerated() {
            // Capture message ID before using in predicate
            let messageId = message.id
            print("📧 Processing email \(index + 1)/\(messages.count): \(message.subject)")
            
            // Find the EmailMessage in the database using traditional fetch
            let descriptor = FetchDescriptor<EmailMessage>()
            
            if let emailMessages = try? modelContext.fetch(descriptor) {
                // Filter in memory to avoid predicate macro issues
                if let emailMessage = emailMessages.first(where: { $0.messageId == messageId }) {
                    // Create a document with email content
                    let content = """
                    From: \(emailMessage.from)
                    Subject: \(emailMessage.subject)
                    Date: \(DateFormatter().string(from: emailMessage.date))
                    
                    \(emailMessage.body)
                    """
                    
                    var metadata: [String: Any] = [
                        "type": "email",
                        "from": emailMessage.from,
                        "subject": emailMessage.subject,
                        "date": ISO8601DateFormatter().string(from: emailMessage.date)
                    ]
                    
                    if let threadId = emailMessage.threadId {
                        metadata["thread_id"] = threadId
                    }
                    
                    // Send to backend for embedding and storage
                    do {
                        print("  → Sending to backend: \(emailMessage.subject)")
                        try await apiClient.upsert(id: emailMessage.id.uuidString, content: content, metadata: metadata)
                        print("✅ Email indexed: \(emailMessage.subject)")
                        emailMessage.isProcessedForAI = true
                        try modelContext.save()
                    } catch {
                        print("❌ Failed to process email \(emailMessage.subject): \(error.localizedDescription)")
                    }
                } else {
                    print("  ⚠️  Email not found in database: \(messageId)")
                }
            } else {
                print("  ⚠️  Failed to fetch emails from database")
            }
        }
        print("✨ Finished processing emails")
    }
    
    private func fetchMessages(accessToken: String, limit: Int) async throws -> [GmailMessage] {
        // Fetch message list
        let listURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(limit)")!
        var listRequest = URLRequest(url: listURL)
        listRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        print("🔄 Fetching Gmail messages from: \(listURL)")
        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
        
        guard let httpResponse = listResponse as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw EmailServiceError.fetchFailed
        }
        
        print("📊 Gmail API response: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse error message from Gmail API
            if let errorJson = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("Gmail API Error: \(message)")
            }
            print("Gmail API returned status code: \(httpResponse.statusCode)")
            throw EmailServiceError.fetchFailed
        }
        
        let messageList = try JSONDecoder().decode(GmailMessageList.self, from: listData)
        print("📋 Gmail returned \(messageList.messages?.count ?? 0) message IDs")
        
        // Fetch full message details
        var messages: [GmailMessage] = []
        
        for messageItem in messageList.messages ?? [] {
            let messageURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageItem.id)")!
            var messageRequest = URLRequest(url: messageURL)
            messageRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (messageData, _) = try await URLSession.shared.data(for: messageRequest)
            let message = try JSONDecoder().decode(GmailMessageDetail.self, from: messageData)
            
            // Parse message
            let parsedMessage = parseGmailMessage(message)
            messages.append(parsedMessage)
        }
        
        print("✅ Successfully fetched and parsed \(messages.count) messages")
        return messages
    }
    
    private func parseGmailMessage(_ detail: GmailMessageDetail) -> GmailMessage {
        let headers = detail.payload.headers
        
        let subject = headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "(No Subject)"
        let from = headers.first(where: { $0.name.lowercased() == "from" })?.value ?? ""
        let to = headers.first(where: { $0.name.lowercased() == "to" })?.value.components(separatedBy: ",") ?? []
        
        let date: Date
        if let dateString = headers.first(where: { $0.name.lowercased() == "date" })?.value {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            date = formatter.date(from: dateString) ?? Date()
        } else {
            date = Date()
        }
        
        let body = detail.payload.body.data ?? detail.snippet
        let isRead = !detail.labelIds.contains("UNREAD")
        
        return GmailMessage(
            id: detail.id,
            threadId: detail.threadId,
            subject: subject,
            from: from,
            fromName: nil,
            to: to,
            body: body,
            snippet: detail.snippet,
            isHTML: detail.payload.mimeType?.contains("html") ?? false,
            date: date,
            isRead: isRead,
            labels: detail.labelIds,
            hasAttachments: detail.payload.parts?.contains(where: { $0.filename != nil && !$0.filename!.isEmpty }) ?? false
        )
    }
    
    private func refreshAccessToken(for account: EmailAccount) async throws {
        let refreshToken = try account.getRefreshToken()
        
        var request = URLRequest(url: URL(string: gmailTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "refresh_token": refreshToken,
            "client_id": gmailClientId,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EmailServiceError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        // Save new access token to Keychain
        try KeychainService.shared.saveToken(
            tokenResponse.accessToken,
            for: account.email,
            type: .accessToken
        )
        
        // Update expiry date
        account.tokenExpiryDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        account.updatedAt = Date()
        
        try modelContext.save()
    }
    
    // MARK: - Disconnect
    
    func disconnectAccount(_ account: EmailAccount) throws {
        account.isConnected = false
        account.tokenExpiryDate = nil
        account.updatedAt = Date()
        
        // Delete tokens from Keychain
        try account.deleteTokens()
        
        try modelContext.save()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension EmailService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

// MARK: - Supporting Types

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let idToken: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case idToken = "id_token"
    }
}

struct UserInfo: Codable {
    let email: String
}

struct GmailMessageList: Codable {
    let messages: [GmailMessageItem]?
}

struct GmailMessageItem: Codable {
    let id: String
    let threadId: String
}

struct GmailMessageDetail: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]
    let snippet: String
    let payload: GmailPayload
}

struct GmailPayload: Codable {
    let headers: [GmailHeader]
    let body: GmailBody
    let mimeType: String?
    let parts: [GmailPart]?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailBody: Codable {
    let data: String?
}

struct GmailPart: Codable {
    let filename: String?
    let body: GmailBody?
}

struct GmailMessage {
    let id: String
    let threadId: String
    let subject: String
    let from: String
    let fromName: String?
    let to: [String]
    let body: String
    let snippet: String
    let isHTML: Bool
    let date: Date
    let isRead: Bool
    let labels: [String]
    let hasAttachments: Bool
}

enum EmailServiceError: LocalizedError {
    case invalidURL
    case authorizationFailed
    case tokenExchangeFailed
    case tokenRefreshFailed
    case userInfoFailed
    case accountNotConnected
    case noRefreshToken
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .authorizationFailed:
            return "Authorization failed"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .userInfoFailed:
            return "Failed to fetch user information"
        case .accountNotConnected:
            return "Email account is not connected"
        case .noRefreshToken:
            return "No refresh token available"
        case .fetchFailed:
            return "Failed to fetch emails"
        }
    }
}

// MARK: - Data Extension for PKCE

extension Data {
    func base64URLEncoded() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
