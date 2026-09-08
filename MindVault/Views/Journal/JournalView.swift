//
//  JournalView.swift
//  MindVault
//
//  Main journal list view
//

import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]
    
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @State private var showingEditor = false
    @State private var selectedEntry: JournalEntry?
    @State private var showingFilters = false
    
    var filteredEntries: [JournalEntry] {
        var result = entries
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category.rawValue }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    EmptyJournalView(showingEditor: $showingEditor)
                } else {
                    journalList
                }
            }
            .navigationTitle("Journal")
            .searchable(text: $searchText, prompt: "Search entries...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            selectedCategory = nil
                        } label: {
                            Label("All Categories", systemImage: "list.bullet")
                        }
                        
                        Divider()
                        
                        ForEach(Category.allCases, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.icon)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if let category = selectedCategory {
                                Text(category.rawValue)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedEntry = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                JournalEditorView(entry: selectedEntry)
            }
        }
    }
    
    private var journalList: some View {
        List {
            // Stats header
            JournalStatsView(entries: entries)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.bottom, 8)
            
            // Entries grouped by date
            ForEach(groupedEntries.keys.sorted().reversed(), id: \.self) { date in
                Section {
                    ForEach(groupedEntries[date] ?? []) { entry in
                        JournalEntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEntry = entry
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    selectedEntry = entry
                                    showingEditor = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    entry.isFavorite.toggle()
                                } label: {
                                    Label(
                                        entry.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: entry.isFavorite ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.yellow)
                            }
                    }
                } header: {
                    Text(formatSectionDate(date))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $selectedEntry) { entry in
            JournalEntryView(entry: entry)
        }
    }
    
    private var groupedEntries: [Date: [JournalEntry]] {
        Dictionary(grouping: filteredEntries) { entry in
            Calendar.current.startOfDay(for: entry.createdAt)
        }
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    private func deleteEntry(_ entry: JournalEntry) {
        // Drop the embedding first, or the assistant keeps citing deleted entries.
        Task { await RAGService.shared.deleteEntry(entry) }
        modelContext.delete(entry)
    }
}

// MARK: - Journal Entry Row
struct JournalEntryRow: View {
    let entry: JournalEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let category = Category(rawValue: entry.category) {
                    Image(systemName: category.icon)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(categoryColor(category).gradient)
                        .clipShape(Circle())
                }
                
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                
                if entry.isEmbedded {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            Text(entry.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            HStack {
                if let mood = entry.mood {
                    if let moodEnum = Mood(rawValue: mood) {
                        Text(moodEnum.emoji)
                    }
                }
                
                Text(entry.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                if !entry.tags.isEmpty {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.indigo.opacity(0.1))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
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
}

// MARK: - Journal Stats View
struct JournalStatsView: View {
    let entries: [JournalEntry]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCard(
                    title: "Total Entries",
                    value: "\(entries.count)",
                    icon: "doc.text.fill",
                    color: .indigo
                )
                
                StatCard(
                    title: "This Week",
                    value: "\(entriesThisWeek)",
                    icon: "calendar",
                    color: .blue
                )
                
                StatCard(
                    title: "AI Ready",
                    value: "\(embeddedCount)",
                    icon: "brain",
                    color: .green
                )
                
                StatCard(
                    title: "Favorites",
                    value: "\(favoritesCount)",
                    icon: "star.fill",
                    color: .yellow
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var entriesThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.filter { $0.createdAt > weekAgo }.count
    }
    
    private var embeddedCount: Int {
        entries.filter { $0.isEmbedded }.count
    }
    
    private var favoritesCount: Int {
        entries.filter { $0.isFavorite }.count
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 120)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty Journal View
struct EmptyJournalView: View {
    @Binding var showingEditor: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 60))
                .foregroundStyle(.indigo.gradient)
            
            Text("Your Journal Awaits")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Start capturing your thoughts, experiences, and memories. Your AI assistant will learn from everything you write.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingEditor = true
            } label: {
                Label("Write First Entry", systemImage: "pencil")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.indigo.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 10)
        }
    }
}

#Preview {
    JournalView()
        .modelContainer(for: [JournalEntry.self], inMemory: true)
}
