//
//  DriveService.swift
//  MindVault
//
//  Google Drive integration service for fetching and processing documents
//

import Foundation
import AuthenticationServices
import CommonCrypto

@MainActor
class DriveService: NSObject, ObservableObject {
    static let shared = DriveService()
    
    // MARK: - Published Properties
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var syncStatus: String = ""
    @Published var currentFolder: DriveFolder = .root
    @Published var files: [DriveFileItem] = []
    
    // MARK: - Private Properties
    private let apiClient = APIClient.shared
    private var accessToken: String?
    private var refreshToken: String?
    
    // OAuth Configuration - see Config.local.xcconfig.example
    private let clientId = Configuration.GoogleOAuth.clientID
    private let redirectUri = Configuration.GoogleOAuth.driveRedirectURI
    private let scope = "https://www.googleapis.com/auth/drive.readonly"
    
    private let tokenKey = "google_drive_token"
    private let refreshTokenKey = "google_drive_refresh_token"
    
    // PKCE code verifier for secure OAuth
    private var codeVerifier: String?
    
    // MARK: - Initialization
    override init() {
        super.init()
        loadSavedToken()
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws {
        guard !clientId.isEmpty else {
            throw DriveError.configurationMissing("Google OAuth Client ID not configured")
        }
        
        // Generate PKCE code verifier and challenge
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier!)
        
        // Build OAuth URL with PKCE
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authURL = components.url else {
            throw DriveError.invalidURL
        }
        
        // Present authentication session
        // The callback URL scheme should be the reversed client ID
        let callbackURLScheme = Configuration.GoogleOAuth.reversedClientID
        
        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: DriveError.authenticationFailed("No authorization code received"))
                    return
                }
                
                continuation.resume(returning: code)
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)
        
        isAuthenticated = true
    }
    
    private func exchangeCodeForTokens(code: String) async throws {
        guard let codeVerifier = codeVerifier else {
            throw DriveError.authenticationFailed("Missing code verifier")
        }
        
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🔐 Token response: \(jsonString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DriveError.authenticationFailed("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            // Try to parse error
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDesc = errorJson["error_description"] as? String {
                throw DriveError.authenticationFailed(errorDesc)
            }
            throw DriveError.authenticationFailed("Token exchange failed with status \(httpResponse.statusCode)")
        }
        
        let tokenResponse = try JSONDecoder().decode(DriveTokenResponse.self, from: data)
        
        accessToken = tokenResponse.access_token
        refreshToken = tokenResponse.refresh_token
        
        saveTokens()
    }
    
    func disconnect() {
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        files = []
        
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
    }
    
    private func loadSavedToken() {
        accessToken = UserDefaults.standard.string(forKey: tokenKey)
        refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey)
        isAuthenticated = accessToken != nil
    }
    
    private func saveTokens() {
        if let accessToken = accessToken {
            UserDefaults.standard.set(accessToken, forKey: tokenKey)
        }
        if let refreshToken = refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        }
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw DriveError.authenticationFailed("No refresh token available")
        }
        
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Refresh failed, need to re-authenticate
            isAuthenticated = false
            throw DriveError.authenticationFailed("Token refresh failed")
        }
        
        let tokenResponse = try JSONDecoder().decode(DriveTokenResponse.self, from: data)
        accessToken = tokenResponse.access_token
        saveTokens()
    }
    
    // MARK: - File Operations
    
    func listFiles(folderId: String = "root") async throws -> [DriveFileItem] {
        guard let accessToken = accessToken else {
            throw DriveError.notAuthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        
        let query = "'\(folderId)' in parents and trashed = false"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,size,modifiedTime,webViewLink,parents)"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "orderBy", value: "folder,name")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Debug: Print the response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📁 Drive API Response: \(jsonString.prefix(500))")
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📁 Drive API Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 401 {
                    // Token expired, try refresh
                    try await refreshAccessToken()
                    return try await listFiles(folderId: folderId)
                }
                
                if httpResponse.statusCode != 200 {
                    // Try to parse error response
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = errorJson["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        throw DriveError.authenticationFailed(message)
                    }
                    throw DriveError.authenticationFailed("HTTP \(httpResponse.statusCode)")
                }
            }
            
            let decoder = JSONDecoder()
            let filesResponse = try decoder.decode(DriveFilesResponse.self, from: data)
            
            let items = (filesResponse.files ?? []).map { file in
                DriveFileItem(
                    id: file.id,
                    name: file.name,
                    mimeType: file.mimeType,
                    size: Int64(file.size ?? "0") ?? 0,
                    modifiedTime: ISO8601DateFormatter().date(from: file.modifiedTime ?? "") ?? Date(),
                    webViewLink: file.webViewLink
                )
            }
            
            files = items
            return items
            
        } catch let decodingError as DecodingError {
            print("❌ Decoding error: \(decodingError)")
            lastError = "Failed to parse Drive response"
            throw DriveError.processingFailed("JSON decoding failed: \(decodingError.localizedDescription)")
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    func downloadFile(fileId: String) async throws -> Data {
        guard let accessToken = accessToken else {
            throw DriveError.notAuthenticated
        }
        
        // First get file metadata to check mime type
        let metadataURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=mimeType,name")!
        var metadataRequest = URLRequest(url: metadataURL)
        metadataRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (metadataData, _) = try await URLSession.shared.data(for: metadataRequest)
        let metadata = try JSONDecoder().decode(DriveFileMetadata.self, from: metadataData)
        
        // Determine download URL based on file type
        let downloadURL: URL
        
        if metadata.mimeType.starts(with: "application/vnd.google-apps.") {
            // Google Docs need to be exported
            let exportMimeType: String
            switch metadata.mimeType {
            case "application/vnd.google-apps.document":
                exportMimeType = "application/pdf"
            case "application/vnd.google-apps.spreadsheet":
                exportMimeType = "text/csv"
            case "application/vnd.google-apps.presentation":
                exportMimeType = "application/pdf"
            default:
                exportMimeType = "text/plain"
            }
            
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/export")!
            components.queryItems = [URLQueryItem(name: "mimeType", value: exportMimeType)]
            downloadURL = components.url!
        } else {
            // Regular files can be downloaded directly
            downloadURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        }
        
        var request = URLRequest(url: downloadURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            return try await downloadFile(fileId: fileId)
        }
        
        return data
    }
    
    // MARK: - Process for RAG
    
    func processDocumentForRAG(fileId: String, filename: String, mimeType: String) async throws -> Int {
        syncStatus = "Downloading \(filename)..."
        
        // Download the file
        let data = try await downloadFile(fileId: fileId)
        
        syncStatus = "Processing \(filename)..."
        
        // Determine actual mime type for Google Docs (they get exported as PDF)
        let actualMimeType: String
        if mimeType.starts(with: "application/vnd.google-apps.document") {
            actualMimeType = "application/pdf"
        } else {
            actualMimeType = mimeType
        }
        
        // Send to backend for processing
        let base64Content = data.base64EncodedString()
        
        let requestBody: [String: Any] = [
            "file_id": fileId,
            "filename": filename,
            "mime_type": actualMimeType,
            "content_base64": base64Content,
            "source": "google_drive"
        ]
        
        let url = URL(string: Configuration.Endpoints.upsertDocument)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        
        let response = try JSONDecoder().decode(DocumentUpsertResponse.self, from: responseData)
        
        if response.success {
            syncStatus = "Indexed \(filename) (\(response.chunks_created) chunks)"
            return response.chunks_created
        } else {
            throw DriveError.processingFailed(response.message)
        }
    }
    
    func syncFolder(folderId: String, recursive: Bool = false) async throws -> (processed: Int, failed: Int) {
        isLoading = true
        defer { isLoading = false }
        
        let files = try await listFiles(folderId: folderId)
        
        var processed = 0
        var failed = 0
        
        for file in files {
            if file.isFolder {
                if recursive {
                    let (subProcessed, subFailed) = try await syncFolder(folderId: file.id, recursive: true)
                    processed += subProcessed
                    failed += subFailed
                }
            } else if file.isSupported {
                do {
                    _ = try await processDocumentForRAG(
                        fileId: file.id,
                        filename: file.name,
                        mimeType: file.mimeType
                    )
                    processed += 1
                } catch {
                    print("❌ Failed to process \(file.name): \(error)")
                    failed += 1
                }
            }
        }
        
        syncStatus = "Synced \(processed) documents, \(failed) failed"
        return (processed, failed)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension DriveService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Supporting Types

struct DriveTokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String
}

struct DriveFilesResponse: Codable {
    let files: [DriveFile]?
    
    // Handle case where "files" key might be missing
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decodeIfPresent([DriveFile].self, forKey: .files)
    }
    
    enum CodingKeys: String, CodingKey {
        case files
    }
}

struct DriveFile: Codable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let modifiedTime: String?
    let webViewLink: String?
    let parents: [String]?
}

struct DriveFileMetadata: Codable {
    let mimeType: String
    let name: String
}

struct DriveFileItem: Identifiable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64
    let modifiedTime: Date
    let webViewLink: String?
    
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
}

struct DocumentUpsertResponse: Codable {
    let success: Bool
    let message: String
    let chunks_created: Int
    let filename: String?
}

enum DriveError: LocalizedError {
    case notAuthenticated
    case authenticationFailed(String)
    case invalidURL
    case configurationMissing(String)
    case processingFailed(String)
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Google Drive"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .configurationMissing(let message):
            return "Configuration missing: \(message)"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}
