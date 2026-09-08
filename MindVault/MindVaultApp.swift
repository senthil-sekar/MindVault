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
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Persist any writes still sitting in LocalVectorStore's debounce
                // window before iOS can suspend or terminate the process.
                Task { await LocalVectorStore.shared.flush() }
            }
        }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isOnboarded: Bool = UserDefaults.standard.bool(forKey: "isOnboarded")
    @Published var selectedTab: Tab = .journal
    
    enum Tab: String, CaseIterable {
        case journal = "Journal"
        case chat = "AI Chat"
        case email = "Email"
        case drive = "Drive"
        case profile = "Profile"
        
        var icon: String {
            switch self {
            case .journal: return "book.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .email: return "envelope.fill"
            case .drive: return "externaldrive.fill"
            case .profile: return "person.fill"
            }
        }
    }
    
    func completeOnboarding() {
        isOnboarded = true
        UserDefaults.standard.set(true, forKey: "isOnboarded")
    }
}
