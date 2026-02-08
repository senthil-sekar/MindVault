//
//  MindVaultApp.swift
//  MindVault - Personal AI Journal Assistant
//
//  Created with AI assistance
//

import SwiftUI
import SwiftData

@main
struct MindVaultApp: App {
    let modelContainer: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                JournalEntry.self,
                ProfileItem.self,
                ChatMessage.self,
                Conversation.self,
                EmailAccount.self,
                EmailMessage.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState())
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isOnboarded: Bool = UserDefaults.standard.bool(forKey: "isOnboarded")
    @Published var selectedTab: Tab = .journal
    @Published var isProcessingEmbeddings: Bool = false
    @Published var embeddingProgress: Double = 0.0
    
    enum Tab: String, CaseIterable {
        case journal = "Journal"
        case chat = "AI Chat"
        case profile = "Profile"
        
        var icon: String {
            switch self {
            case .journal: return "book.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .profile: return "person.fill"
            }
        }
    }
    
    func completeOnboarding() {
        isOnboarded = true
        UserDefaults.standard.set(true, forKey: "isOnboarded")
    }
}
