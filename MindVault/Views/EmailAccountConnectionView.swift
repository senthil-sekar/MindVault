//
//  EmailAccountConnectionView.swift
//  MindVault
//
//  Created with AI assistance
//

import SwiftUI
import SwiftData

struct EmailAccountConnectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var emailService: EmailService
    
    @State private var selectedProvider: EmailProvider = .gmail
    @State private var showError = false
    @State private var errorMessage = ""
    
    init(modelContext: ModelContext) {
        _emailService = StateObject(wrappedValue: EmailService(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "envelope.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.blue.gradient)
                            
                            Text("Connect Email Account")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Connect your email to automatically import messages as journal entries")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 32)
                        
                        // Provider Selection
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Select Email Provider")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                ForEach(EmailProvider.allCases, id: \.self) { provider in
                                    ProviderButton(
                                        provider: provider,
                                        isSelected: selectedProvider == provider
                                    ) {
                                        selectedProvider = provider
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Features
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What you can do")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                FeatureRow(
                                    icon: "book.fill",
                                    title: "Convert to Journal",
                                    description: "Transform emails into journal entries"
                                )
                                
                                FeatureRow(
                                    icon: "brain.head.profile",
                                    title: "AI Insights",
                                    description: "Get insights from your email conversations"
                                )
                                
                                FeatureRow(
                                    icon: "lock.shield.fill",
                                    title: "Secure & Private",
                                    description: "Your data stays on your device"
                                )
                            }
                            .padding(.horizontal)
                        }
                        
                        Spacer(minLength: 32)
                        
                        // Connect Button
                        VStack(spacing: 12) {
                            Button(action: connectAccount) {
                                HStack {
                                    if emailService.isConnecting {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "link")
                                        Text("Connect \(selectedProvider.rawValue)")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedProvider == .gmail ? Color.red : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(emailService.isConnecting || selectedProvider == .outlook || selectedProvider == .icloud || selectedProvider == .other)
                            
                            if selectedProvider != .gmail {
                                Text("\(selectedProvider.rawValue) support coming soon")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }
                
                if emailService.isConnecting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Connecting to \(selectedProvider.rawValue)...")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(emailService.isConnecting)
                }
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func connectAccount() {
        Task {
            do {
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first else {
                    return
                }
                
                let account = try await emailService.connectGmailAccount(presentationAnchor: window)
                
                // Start initial sync
                try await emailService.syncEmails(for: account, limit: 50)
                
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Supporting Views

struct ProviderButton: View {
    let provider: EmailProvider
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: provider.iconName)
                    .font(.title2)
                    .foregroundColor(providerColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if provider != .gmail {
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(providerColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? providerColor.opacity(0.1) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? providerColor : Color.clear, lineWidth: 2)
            )
        }
        .disabled(provider != .gmail)
    }
    
    private var providerColor: Color {
        switch provider {
        case .gmail: return .red
        case .outlook: return .blue
        case .icloud: return .blue
        case .other: return .gray
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue.gradient)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    EmailAccountConnectionView(modelContext: ModelContext(try! ModelContainer(for: EmailAccount.self)))
}
