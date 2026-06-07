//
//  EmailListView.swift
//  MindVault
//
//  Created with AI assistance
//

import SwiftUI
import SwiftData

struct EmailListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmailMessage.date, order: .reverse) private var messages: [EmailMessage]
    @Query private var accounts: [EmailAccount]
    
    @StateObject private var emailService = EmailService.placeholder
    @StateObject private var processingService = EmailProcessingService.placeholder
    @State private var selectedMessage: EmailMessage?
    @State private var showAccountConnection = false
    @State private var selectedAccount: EmailAccount?
    @State private var showSyncProgress = false
    @State private var showProcessingAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    emptyStateView
                } else if messages.isEmpty {
                    noMessagesView
                } else {
                    messagesList
                }
            }
            .navigationTitle("Emails")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showAccountConnection = true
                        } label: {
                            Label("Add Account", systemImage: "plus")
                        }
                        
                        if let account = accounts.first {
                            // Quick sync (latest 50 emails)
                            Button {
                                syncEmails(for: account)
                            } label: {
                                Label("Quick Sync", systemImage: "arrow.clockwise")
                            }
                            .disabled(emailService.isSyncing)
                            
                            // Full sync (latest 200 emails)
                            Button {
                                fullSyncEmails(for: account)
                            } label: {
                                Label("Full Sync (200 emails)", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(emailService.isSyncing)
                            
                            Divider()
                            
                            // Cleanup deleted emails
                            Button {
                                cleanupDeletedEmails(for: account)
                            } label: {
                                Label("Cleanup Deleted", systemImage: "trash.circle")
                            }
                            .disabled(emailService.isSyncing)
                            
                            // Clear all & resync
                            Button(role: .destructive) {
                                clearAllAndResync(for: account)
                            } label: {
                                Label("Clear All & Resync", systemImage: "trash.fill")
                            }
                            .disabled(emailService.isSyncing)
                            
                            Divider()
                            
                            // Auto-sync toggle
                            Button {
                                emailService.toggleAutoSync(for: account)
                            } label: {
                                Label(
                                    emailService.autoSyncEnabled ? "Disable Auto-Sync" : "Enable Auto-Sync",
                                    systemImage: emailService.autoSyncEnabled ? "clock.badge.checkmark" : "clock"
                                )
                            }
                            
                            Divider()
                            
                            Button {
                                processEmailsForAI(for: account)
                            } label: {
                                Label("Process for AI", systemImage: "brain")
                            }
                            .disabled(processingService.isProcessing)
                            
                            Divider()
                            
                            // Disconnect account
                            Button(role: .destructive) {
                                disconnectAccount(account)
                            } label: {
                                Label("Disconnect Account", systemImage: "person.crop.circle.badge.minus")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showAccountConnection) {
                EmailAccountConnectionView(modelContext: modelContext)
            }
            .sheet(item: $selectedMessage) { message in
                EmailDetailView(message: message, modelContext: modelContext)
            }
            .onAppear {
                // Inject modelContext into services (available after view appears)
                emailService.setModelContext(modelContext)
                processingService.setModelContext(modelContext)
                // Start auto-sync when view appears
                if let account = accounts.first, account.isConnected {
                    emailService.startAutoSync(for: account)
                }
            }
            .onDisappear {
                emailService.stopAutoSync()
            }
            .overlay {
                if emailService.isSyncing {
                    syncProgressView
                }
                
                if processingService.isProcessing {
                    processingProgressView
                }
            }
            .alert("Processing Complete", isPresented: $showProcessingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Emails have been processed and added to AI context.")
            }
            .alert("Sync Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
            
            VStack(spacing: 8) {
                Text("No Email Account Connected")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Connect your email account to start importing messages")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                showAccountConnection = true
            } label: {
                Label("Connect Email Account", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
    
    private var noMessagesView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundStyle(.gray.gradient)
            
            VStack(spacing: 8) {
                Text("No Messages Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Sync your emails to see them here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let account = accounts.first {
                // Check if account is connected
                if !account.isConnected {
                    VStack(spacing: 12) {
                        Text("Account disconnected")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Button {
                            showAccountConnection = true
                        } label: {
                            Label("Reconnect Account", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        if emailService.isSyncing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Syncing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Button {
                                syncEmails(for: account)
                            } label: {
                                Label("Sync Now", systemImage: "arrow.clockwise")
                                    .font(.headline)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        
                        // Show last error if any
                        if let error = emailService.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
    
    private var messagesList: some View {
        List {
            ForEach(messages) { message in
                EmailMessageRow(message: message)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedMessage = message
                    }
            }
            .onDelete { indexSet in
                deleteEmails(at: indexSet)
            }
        }
        .listStyle(.plain)
        .refreshable {
            if let account = accounts.first {
                syncEmails(for: account)
            }
        }
    }
    
    private var syncProgressView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView(value: emailService.syncProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("Syncing emails...")
                    .font(.headline)
                
                Text("\(Int(emailService.syncProgress * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(32)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
    
    private var processingProgressView: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView(value: processingService.processingProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("Processing for AI...")
                    .font(.headline)
                
                Text("\(Int(processingService.processingProgress * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(32)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
    
    private func syncEmails(for account: EmailAccount) {
        Task {
            do {
                try await emailService.syncEmails(for: account, limit: 50)
            } catch {
                print("Sync failed: \(error.localizedDescription)")
                errorMessage = "Sync failed: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    private func fullSyncEmails(for account: EmailAccount) {
        Task {
            do {
                try await emailService.syncEmails(for: account, limit: 200)
            } catch {
                print("Full sync failed: \(error.localizedDescription)")
                errorMessage = "Full sync failed: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    private func cleanupDeletedEmails(for account: EmailAccount) {
        Task {
            do {
                try await emailService.cleanupDeletedEmails(for: account)
            } catch {
                print("Cleanup failed: \(error.localizedDescription)")
                errorMessage = "Cleanup failed: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    private func clearAllAndResync(for account: EmailAccount) {
        Task {
            do {
                try await emailService.clearAllEmailsAndResync(for: account)
            } catch {
                print("Clear & resync failed: \(error.localizedDescription)")
                errorMessage = "Clear & resync failed: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    private func deleteEmails(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let email = messages[index]
                
                // Delete from vector DB if processed
                if email.isProcessedForAI {
                    do {
                        try await APIClient.shared.delete(id: email.id.uuidString)
                        print("✅ Deleted from vector DB: \(email.subject)")
                    } catch {
                        print("⚠️ Failed to delete from vector DB: \(error.localizedDescription)")
                    }
                }
                
                // Delete from local DB
                modelContext.delete(email)
            }
            
            try? modelContext.save()
        }
    }
    
    private func processEmailsForAI(for account: EmailAccount) {
        Task {
            do {
                try await emailService.processExistingEmails(for: account)
                showProcessingAlert = true
            } catch {
                print("Processing failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func disconnectAccount(_ account: EmailAccount) {
        Task {
            // Delete all emails for this account from vector DB
            let accountEmails = messages.filter { $0.account?.id == account.id }
            for email in accountEmails {
                if email.isProcessedForAI {
                    try? await APIClient.shared.delete(id: email.id.uuidString)
                }
                modelContext.delete(email)
            }
            
            // Delete the account itself
            modelContext.delete(account)
            try? modelContext.save()
            
            print("✅ Account disconnected and all data removed")
        }
    }
}

// MARK: - Email Message Row

struct EmailMessageRow: View {
    let message: EmailMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.fromName ?? message.from)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(message.isRead ? .secondary : .primary)
                    
                    Text(message.subject)
                        .font(.body)
                        .fontWeight(message.isRead ? .regular : .semibold)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if message.convertedToJournal {
                        Image(systemName: "book.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            if let snippet = message.bodySnippet {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack(spacing: 8) {
                if message.isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                
                if message.hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if message.isProcessedForAI {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                
                if let labels = message.labels, !labels.isEmpty {
                    ForEach(labels.prefix(2), id: \.self) { label in
                        Text(label.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let container = try! ModelContainer(for: EmailAccount.self, EmailMessage.self)
    return EmailListView()
        .modelContainer(container)
}

