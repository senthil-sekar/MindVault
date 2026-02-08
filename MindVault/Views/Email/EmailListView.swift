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
    
    @StateObject private var emailService: EmailService
    @StateObject private var processingService: EmailProcessingService
    @State private var selectedMessage: EmailMessage?
    @State private var showAccountConnection = false
    @State private var selectedAccount: EmailAccount?
    @State private var showSyncProgress = false
    @State private var showProcessingAlert = false
    
    init(modelContext: ModelContext) {
        _emailService = StateObject(wrappedValue: EmailService(modelContext: modelContext))
        _processingService = StateObject(wrappedValue: EmailProcessingService(modelContext: modelContext))
    }
    
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
                            Button {
                                syncEmails(for: account)
                            } label: {
                                Label("Sync Emails", systemImage: "arrow.clockwise")
                            }
                            .disabled(emailService.isSyncing)
                            
                            Divider()
                            
                            Button {
                                processEmailsForAI(for: account)
                            } label: {
                                Label("Process for AI", systemImage: "brain")
                            }
                            .disabled(processingService.isProcessing)
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
                .disabled(emailService.isSyncing)
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
            }
        }
    }
    
    private func processEmailsForAI(for account: EmailAccount) {
        Task {
            do {
                try await processingService.processUnprocessedEmails(for: account)
                showProcessingAlert = true
            } catch {
                print("Processing failed: \(error.localizedDescription)")
            }
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
    EmailListView(modelContext: ModelContext(try! ModelContainer(for: EmailAccount.self, EmailMessage.self)))
}
