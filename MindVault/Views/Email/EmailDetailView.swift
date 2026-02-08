//
//  EmailDetailView.swift
//  MindVault
//
//  Created with AI assistance
//

import SwiftUI
import SwiftData

struct EmailDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let message: EmailMessage
    @State private var showConvertSheet = false
    @State private var journalTitle = ""
    @State private var journalContent = ""
    @State private var showSuccessAlert = false
    
    init(message: EmailMessage, modelContext: ModelContext) {
        self.message = message
        _journalTitle = State(initialValue: message.subject)
        _journalContent = State(initialValue: message.body)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message.subject)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("From")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(message.fromName ?? message.from)
                                    .font(.subheadline)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Date")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(message.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                            }
                        }
                        
                        Divider()
                        
                        if !message.to.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("To")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(message.to.joined(separator: ", "))
                                    .font(.subheadline)
                            }
                        }
                        
                        if let cc = message.cc, !cc.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CC")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(cc.joined(separator: ", "))
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Labels and Status
                    HStack(spacing: 12) {
                        if message.isStarred {
                            Label("Starred", systemImage: "star.fill")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(6)
                        }
                        
                        if message.hasAttachments {
                            Label("\(message.attachmentCount) attachment\(message.attachmentCount == 1 ? "" : "s")", systemImage: "paperclip")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(6)
                        }
                        
                        if message.convertedToJournal {
                            Label("In Journal", systemImage: "book.fill")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                    
                    Divider()
                    
                    // Body
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.headline)
                        
                        if message.isHTML {
                            // For HTML content, strip basic tags
                            Text(stripHTMLTags(from: message.body))
                                .font(.body)
                        } else {
                            Text(message.body)
                                .font(.body)
                        }
                    }
                    
                    // Convert to Journal Button
                    if !message.convertedToJournal {
                        Button {
                            showConvertSheet = true
                        } label: {
                            Label("Convert to Journal Entry", systemImage: "book.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.top, 12)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Already converted to journal entry")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showConvertSheet) {
                ConvertToJournalSheet(
                    title: $journalTitle,
                    content: $journalContent,
                    onConvert: convertToJournal
                )
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Email converted to journal entry successfully!")
            }
        }
    }
    
    private func stripHTMLTags(from html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        return result
    }
    
    private func convertToJournal() {
        let entry = JournalEntry(
            title: journalTitle,
            content: journalContent,
            tags: ["email", "imported"],
            mood: "neutral"
        )
        
        modelContext.insert(entry)
        
        message.convertedToJournal = true
        message.journalEntryId = entry.id
        
        do {
            try modelContext.save()
            showSuccessAlert = true
        } catch {
            print("Failed to save: \(error.localizedDescription)")
        }
    }
}

// MARK: - Convert to Journal Sheet

struct ConvertToJournalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var content: String
    let onConvert: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Journal Entry Title") {
                    TextField("Title", text: $title)
                }
                
                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                }
                
                Section {
                    Text("The email will be converted into a journal entry. You can edit the title and content above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Convert to Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Convert") {
                        onConvert()
                        dismiss()
                    }
                    .disabled(title.isEmpty || content.isEmpty)
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: EmailMessage.self, configurations: config)
    let context = container.mainContext
    
    let message = EmailMessage(
        messageId: "123",
        subject: "Test Email",
        from: "sender@example.com",
        fromName: "John Doe",
        to: ["recipient@example.com"],
        body: "This is a test email body with some content to display.",
        date: Date()
    )
    
    return EmailDetailView(message: message, modelContext: context)
}
