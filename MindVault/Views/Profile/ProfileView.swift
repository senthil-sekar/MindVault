//
//  ProfileView.swift
//  MindVault
//
//  Profile management view with education, experience, and skills
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProfileItem.createdAt, order: .reverse) private var profileItems: [ProfileItem]
    
    @State private var selectedType: ProfileType = .skill
    @State private var showingEditor = false
    @State private var selectedItem: ProfileItem?
    @State private var showingSettings = false
    
    var filteredItems: [ProfileItem] {
        profileItems.filter { $0.type == selectedType.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Profile Header
                profileHeader
                
                // Type Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ProfileType.allCases, id: \.self) { type in
                            TypeChip(
                                type: type,
                                count: profileItems.filter { $0.type == type.rawValue }.count,
                                isSelected: selectedType == type
                            ) {
                                withAnimation {
                                    selectedType = type
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Content
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    itemsList
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedItem = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                ProfileItemEditorView(item: selectedItem, defaultType: selectedType)
            }
            .sheet(item: $selectedItem) { item in
                ProfileItemDetailView(item: item)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(.indigo.gradient)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            
            // Stats
            HStack(spacing: 30) {
                ProfileStat(title: "Skills", count: profileItems.filter { $0.type == ProfileType.skill.rawValue }.count)
                ProfileStat(title: "Experience", count: profileItems.filter { $0.type == ProfileType.experience.rawValue }.count)
                ProfileStat(title: "Education", count: profileItems.filter { $0.type == ProfileType.education.rawValue }.count)
            }
            
            // AI Sync Status
            let embeddedCount = profileItems.filter { $0.isEmbedded }.count
            HStack {
                Image(systemName: "brain")
                    .foregroundStyle(.green)
                Text("\(embeddedCount)/\(profileItems.count) synced to AI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.green.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.1), .purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    // MARK: - Items List
    private var itemsList: some View {
        List {
            ForEach(filteredItems) { item in
                ProfileItemRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            selectedItem = item
                            showingEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: selectedType.icon)
                .font(.system(size: 50))
                .foregroundStyle(.indigo.gradient)
            
            Text("No \(selectedType.rawValue)s Yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Add your \(selectedType.rawValue.lowercased())s to help your AI assistant understand you better.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingEditor = true
            } label: {
                Label("Add \(selectedType.rawValue)", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.indigo.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
        }
    }
    
    private func deleteItem(_ item: ProfileItem) {
        modelContext.delete(item)
    }
}

// MARK: - Profile Stat
struct ProfileStat: View {
    let title: String
    let count: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Type Chip
struct TypeChip: View {
    let type: ProfileType
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.caption)
                Text(type.rawValue)
                    .font(.subheadline)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? typeColor.gradient : Color(.systemGray5).gradient)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
    
    private var typeColor: Color {
        switch type.color {
        case "yellow": return .yellow
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "teal": return .teal
        case "red": return .red
        case "indigo": return .indigo
        default: return .gray
        }
    }
}

// MARK: - Profile Item Row
struct ProfileItemRow: View {
    let item: ProfileItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.headline)
                
                Spacer()
                
                if item.isEmbedded {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                if let level = item.proficiencyLevel {
                    ProficiencyBadge(level: level)
                }
            }
            
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if !item.content.isEmpty {
                Text(item.content)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            
            HStack {
                if let start = item.startDate {
                    Text(formatDateRange(start: start, end: item.endDate, isCurrent: item.isCurrent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !item.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
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
    
    private func formatDateRange(start: Date, end: Date?, isCurrent: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        
        var result = formatter.string(from: start)
        if let end = end {
            result += " - \(formatter.string(from: end))"
        } else if isCurrent {
            result += " - Present"
        }
        
        return result
    }
}

// MARK: - Proficiency Badge
struct ProficiencyBadge: View {
    let level: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= level ? Color.yellow : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var emailAccounts: [EmailAccount]
    
    @AppStorage("serverURL") private var serverURL = "http://localhost:8000"
    @AppStorage("openAIKey") private var openAIKey = ""
    @AppStorage("autoSync") private var autoSync = true
    
    @State private var showEmailConnection = false
    @State private var showEmailList = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Email Accounts") {
                    if emailAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                showEmailConnection = true
                            } label: {
                                Label("Connect Email Account", systemImage: "envelope.badge.fill")
                            }
                            
                            Text("Connect your email to automatically import and analyze your emails. All data stays on your device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(emailAccounts) { account in
                            EmailAccountRow(account: account) {
                                showEmailList = true
                            }
                        }
                        
                        Button {
                            showEmailConnection = true
                        } label: {
                            Label("Add Another Account", systemImage: "plus")
                        }
                    }
                }
                
                Section("AI Backend") {
                    TextField("Server URL", text: $serverURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    TextField("OpenAI API Key (optional)", text: $openAIKey)
                        .autocapitalization(.none)
                }
                
                Section("Sync Settings") {
                    Toggle("Auto-sync new entries", isOn: $autoSync)
                    
                    Button("Sync All Now") {
                        // Trigger sync
                    }
                    
                    Button("Clear AI Data", role: .destructive) {
                        // Clear embeddings
                    }
                }
                
                Section("Data") {
                    Button("Export All Data") {
                        // Export
                    }
                    
                    Button("Import Data") {
                        // Import
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://mindvault.app/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://mindvault.app/terms")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEmailConnection) {
                EmailAccountConnectionView(modelContext: modelContext)
            }
            .sheet(isPresented: $showEmailList) {
                EmailListView(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Email Account Row
struct EmailAccountRow: View {
    let account: EmailAccount
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: account.provider.iconName)
                    .font(.title2)
                    .foregroundColor(providerColor)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.email)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text(account.provider.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if account.isConnected {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                Text("Connected")
                                    .font(.caption2)
                            }
                            .foregroundColor(.green)
                        } else {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption2)
                                Text("Disconnected")
                                    .font(.caption2)
                            }
                            .foregroundColor(.orange)
                        }
                    }
                    
                    if let lastSync = account.lastSyncDate {
                        Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var providerColor: Color {
        switch account.provider {
        case .gmail: return .red
        case .outlook: return .blue
        case .icloud: return .blue
        case .other: return .gray
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [ProfileItem.self], inMemory: true)
}
