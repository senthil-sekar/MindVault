//
//  ContentView.swift
//  MindVault
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if appState.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            JournalView()
                .tabItem {
                    Label(AppState.Tab.journal.rawValue, systemImage: AppState.Tab.journal.icon)
                }
                .tag(AppState.Tab.journal)
            
            ChatView()
                .tabItem {
                    Label(AppState.Tab.chat.rawValue, systemImage: AppState.Tab.chat.icon)
                }
                .tag(AppState.Tab.chat)
            
            ProfileView()
                .tabItem {
                    Label(AppState.Tab.profile.rawValue, systemImage: AppState.Tab.profile.icon)
                }
                .tag(AppState.Tab.profile)
        }
        .tint(.indigo)
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    
    let pages: [(title: String, description: String, icon: String)] = [
        ("Welcome to MindVault", "Your personal AI-powered journal that remembers everything about you.", "brain.head.profile"),
        ("Capture Your Life", "Write about your experiences, skills, education, and personal growth.", "pencil.and.outline"),
        ("Ask Anything", "Your AI assistant knows your entire history and can answer any question about you.", "sparkles")
    ]
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    VStack(spacing: 20) {
                        Image(systemName: pages[index].icon)
                            .font(.system(size: 80))
                            .foregroundStyle(.indigo.gradient)
                        
                        Text(pages[index].title)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text(pages[index].description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 350)
            
            Spacer()
            
            Button {
                if currentPage < pages.count - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    appState.completeOnboarding()
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.indigo.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.1), .purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
