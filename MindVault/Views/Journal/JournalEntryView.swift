//
//  JournalEntryView.swift
//  MindVault
//
//  Detail view for a journal entry
//

import SwiftUI
import SwiftData

struct JournalEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let entry: JournalEntry
    
    @State private var showingEditor = false
    @State private var showingDeleteAlert = false
    @StateObject private var ragService = RAGService.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection
                    
                    Divider()
                    
                    // Content
                    contentSection
                    
                    // Tags
                    if !entry.tags.isEmpty {
                        tagsSection
                    }
                    
                    // Metadata
                    metadataSection
                    
                    // AI Status
                    aiStatusSection
                }
                .padding()
            }
            .navigationTitle("Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button {
                            entry.isFavorite.toggle()
                        } label: {
                            Label(
                                entry.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                systemImage: entry.isFavorite ? "star.slash" : "star"
                            )
                        }
                        
                        Button {
                            shareEntry()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        if !entry.isEmbedded {
                            Button {
                                Task {
                                    await embedEntry()
                                }
                            } label: {
                                Label("Sync to AI", systemImage: "brain")
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                JournalEditorView(entry: entry)
            }
            .alert("Delete Entry", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
            } message: {
                Text("Are you sure you want to delete this entry? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let category = Category(rawValue: entry.category) {
                    Label(category.rawValue, systemImage: category.icon)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(categoryColor(category).opacity(0.2))
                        .foregroundStyle(categoryColor(category))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            
            Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                .font(.title)
                .fontWeight(.bold)
            
            HStack {
                if let mood = entry.mood, let moodEnum = Mood(rawValue: mood) {
                    HStack(spacing: 4) {
                        Text(moodEnum.emoji)
                        Text(moodEnum.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text(entry.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Content Section
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.content)
                .font(.body)
                .lineSpacing(6)
        }
    }
    
    // MARK: - Tags Section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)
            
            FlowLayout(spacing: 8) {
                ForEach(entry.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.indigo.opacity(0.1))
                        .foregroundStyle(.indigo)
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Metadata Section
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)
            
            VStack(spacing: 12) {
                MetadataRow(icon: "calendar", title: "Created", value: entry.createdAt.formatted())
                
                if entry.createdAt != entry.updatedAt {
                    MetadataRow(icon: "pencil", title: "Updated", value: entry.updatedAt.formatted())
                }
                
                if let location = entry.locationName {
                    MetadataRow(icon: "location", title: "Location", value: location)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - AI Status Section
    private var aiStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Integration")
                .font(.headline)
            
            HStack {
                Image(systemName: entry.isEmbedded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.isEmbedded ? .green : .secondary)
                
                VStack(alignment: .leading) {
                    Text(entry.isEmbedded ? "Synced to AI" : "Not synced")
                        .font(.subheadline)
                    Text(entry.isEmbedded ? "Your AI assistant can access this entry" : "Sync to enable AI to learn from this entry")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !entry.isEmbedded {
                    Button("Sync") {
                        Task {
                            await embedEntry()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Helper Functions
    private func categoryColor(_ category: Category) -> Color {
        switch category.color {
        case "indigo": return .indigo
        case "blue": return .blue
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return .pink
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "teal": return .teal
        case "mint": return .mint
        case "cyan": return .cyan
        default: return .gray
        }
    }
    
    private func shareEntry() {
        let text = """
        \(entry.title)
        
        \(entry.content)
        
        ---
        Written in MindVault
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func embedEntry() async {
        await ragService.embedJournalEntry(entry)
    }
    
    private func deleteEntry() {
        modelContext.delete(entry)
        dismiss()
    }
}

// MARK: - Metadata Row
struct MetadataRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(title)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
        }
        .font(.subheadline)
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                
                self.size.width = max(self.size.width, currentX)
            }
            
            self.size.height = currentY + lineHeight
        }
    }
}

#Preview {
    JournalEntryView(entry: JournalEntry(
        title: "My First Entry",
        content: "This is a sample journal entry with some content to preview how it looks in the app.",
        category: Category.personal.rawValue,
        tags: ["reflection", "personal", "growth"]
    ))
}
