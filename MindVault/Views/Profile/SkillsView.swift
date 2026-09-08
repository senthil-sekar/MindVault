//
//  SkillsView.swift
//  MindVault
//
//  Profile item editor and detail views
//

import SwiftUI
import SwiftData

// MARK: - Profile Item Editor View
struct ProfileItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let item: ProfileItem?
    let defaultType: ProfileType
    
    @State private var type: ProfileType = .skill
    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var content: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var hasStartDate: Bool = false
    @State private var hasEndDate: Bool = false
    @State private var isCurrent: Bool = false
    @State private var proficiencyLevel: Int = 3
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    
    @State private var isSaving = false
    @StateObject private var ragService = RAGService.shared
    
    var isNewItem: Bool { item == nil }
    
    var body: some View {
        NavigationStack {
            Form {
                // Type Section
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ProfileType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.icon)
                                .tag(t)
                        }
                    }
                }
                
                // Title Section
                Section {
                    TextField(titlePlaceholder, text: $title)
                        .font(.headline)
                    
                    if showsSubtitle {
                        TextField(subtitlePlaceholder, text: $subtitle)
                    }
                } header: {
                    Text("Title")
                }
                
                // Proficiency Section (for skills)
                if type == .skill || type == .language {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Proficiency: \(proficiencyLabel)")
                                .font(.subheadline)
                            
                            HStack {
                                ForEach(1...5, id: \.self) { level in
                                    Button {
                                        proficiencyLevel = level
                                    } label: {
                                        Image(systemName: level <= proficiencyLevel ? "star.fill" : "star")
                                            .font(.title2)
                                            .foregroundStyle(level <= proficiencyLevel ? .yellow : .gray)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Proficiency Level")
                    }
                }
                
                // Date Section
                if showsDates {
                    Section {
                        Toggle("Has Start Date", isOn: $hasStartDate)
                        
                        if hasStartDate {
                            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            
                            Toggle("Currently Active", isOn: $isCurrent)
                            
                            if !isCurrent {
                                Toggle("Has End Date", isOn: $hasEndDate)
                                
                                if hasEndDate {
                                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                                }
                            }
                        }
                    } header: {
                        Text("Duration")
                    }
                }
                
                // Description Section
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Describe your \(type.rawValue.lowercased()) in detail. The more information you provide, the better your AI assistant will understand you.")
                }
                
                // Tags Section
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.indigo.opacity(0.1))
                            .foregroundStyle(.indigo)
                            .clipShape(Capsule())
                        }
                    }
                    
                    HStack {
                        TextField("Add keyword", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        Button("Add") {
                            addTag()
                        }
                        .disabled(newTag.isEmpty)
                    }
                } header: {
                    Text("Keywords & Tags")
                } footer: {
                    Text("Add relevant keywords to help with search and AI understanding.")
                }
            }
            .navigationTitle(isNewItem ? "Add \(type.rawValue)" : "Edit \(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveItem()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
            .onAppear {
                loadItemData()
            }
        }
    }
    
    // MARK: - Computed Properties
    private var titlePlaceholder: String {
        switch type {
        case .skill: return "Skill name (e.g., Swift, Machine Learning)"
        case .education: return "Degree or Program"
        case .experience: return "Job Title"
        case .certification: return "Certification Name"
        case .project: return "Project Name"
        case .achievement: return "Achievement Title"
        case .language: return "Language"
        case .interest: return "Interest/Hobby"
        case .value: return "Value/Principle"
        }
    }
    
    private var subtitlePlaceholder: String {
        switch type {
        case .education: return "Institution"
        case .experience: return "Company"
        case .certification: return "Issuing Organization"
        case .project: return "Associated with"
        default: return "Details"
        }
    }
    
    private var showsSubtitle: Bool {
        [.education, .experience, .certification, .project].contains(type)
    }
    
    private var showsDates: Bool {
        [.education, .experience, .certification, .project].contains(type)
    }
    
    private var proficiencyLabel: String {
        switch proficiencyLevel {
        case 1: return "Beginner"
        case 2: return "Elementary"
        case 3: return "Intermediate"
        case 4: return "Advanced"
        case 5: return "Expert"
        default: return "Unknown"
        }
    }
    
    // MARK: - Functions
    private func loadItemData() {
        type = defaultType
        
        if let item = item {
            type = ProfileType(rawValue: item.type) ?? defaultType
            title = item.title
            subtitle = item.subtitle ?? ""
            content = item.content
            tags = item.tags
            proficiencyLevel = item.proficiencyLevel ?? 3
            isCurrent = item.isCurrent
            
            if let start = item.startDate {
                hasStartDate = true
                startDate = start
            }
            
            if let end = item.endDate {
                hasEndDate = true
                endDate = end
            }
        }
    }
    
    private func addTag() {
        let cleanedTag = newTag.trimmingCharacters(in: .whitespaces)
            .lowercased()
        
        if !cleanedTag.isEmpty && !tags.contains(cleanedTag) {
            tags.append(cleanedTag)
        }
        newTag = ""
    }
    
    private func saveItem() {
        isSaving = true
        
        if let item = item {
            // Update existing
            item.type = type.rawValue
            item.title = title
            item.subtitle = subtitle.isEmpty ? nil : subtitle
            item.content = content
            item.tags = tags
            item.proficiencyLevel = (type == .skill || type == .language) ? proficiencyLevel : nil
            item.startDate = hasStartDate ? startDate : nil
            item.endDate = hasEndDate && !isCurrent ? endDate : nil
            item.isCurrent = isCurrent
            item.updatedAt = Date()
            item.isEmbedded = false  // Mark for re-embedding
        } else {
            // Create new
            let newItem = ProfileItem(
                type: type.rawValue,
                title: title,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                content: content,
                startDate: hasStartDate ? startDate : nil,
                endDate: hasEndDate && !isCurrent ? endDate : nil,
                isCurrent: isCurrent,
                tags: tags,
                proficiencyLevel: (type == .skill || type == .language) ? proficiencyLevel : nil
            )
            modelContext.insert(newItem)
            
            // Trigger embedding
            Task {
                await ragService.embedProfileItem(newItem)
            }
        }
        
        isSaving = false
        dismiss()
    }
}

// MARK: - Profile Item Detail View
struct ProfileItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let item: ProfileItem
    
    @State private var showingEditor = false
    @State private var showingDeleteAlert = false
    @StateObject private var ragService = RAGService.shared
    
    var itemType: ProfileType {
        ProfileType(rawValue: item.type) ?? .skill
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection
                    
                    Divider()
                    
                    // Content
                    if !item.content.isEmpty {
                        contentSection
                    }
                    
                    // Tags
                    if !item.tags.isEmpty {
                        tagsSection
                    }
                    
                    // Dates
                    if item.startDate != nil {
                        dateSection
                    }
                    
                    // AI Status
                    aiStatusSection
                }
                .padding()
            }
            .navigationTitle(itemType.rawValue)
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
                        
                        if !item.isEmbedded {
                            Button {
                                Task {
                                    await ragService.embedProfileItem(item)
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
                ProfileItemEditorView(item: item, defaultType: itemType)
            }
            .alert("Delete \(itemType.rawValue)", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteItem()
                }
            } message: {
                Text("Are you sure you want to delete this \(itemType.rawValue.lowercased())?")
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: itemType.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(typeColor.gradient)
                    .clipShape(Circle())
                
                Spacer()
                
                if item.isEmbedded {
                    Label("AI Synced", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            Text(item.title)
                .font(.title)
                .fontWeight(.bold)
            
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            if let level = item.proficiencyLevel {
                HStack(spacing: 4) {
                    Text("Proficiency:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= level ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(i <= level ? .yellow : .gray)
                        }
                    }
                    
                    Text("(\(proficiencyLabel(level)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Content Section
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            
            Text(item.content)
                .font(.body)
        }
    }
    
    // MARK: - Tags Section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keywords")
                .font(.headline)
            
            FlowLayout(spacing: 8) {
                ForEach(item.tags, id: \.self) { tag in
                    Text(tag)
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
    
    // MARK: - Date Section
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Started")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let start = item.startDate {
                        Text(start, format: .dateTime.month().year())
                            .font(.subheadline)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(item.isCurrent ? "Present" : "Ended")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if item.isCurrent {
                        Text("Current")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else if let end = item.endDate {
                        Text(end, format: .dateTime.month().year())
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if let years = item.durationYears {
                Text("Duration: \(String(format: "%.1f", years)) years")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - AI Status Section
    private var aiStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Integration")
                .font(.headline)
            
            HStack {
                Image(systemName: item.isEmbedded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isEmbedded ? .green : .secondary)
                
                VStack(alignment: .leading) {
                    Text(item.isEmbedded ? "Synced to AI" : "Not synced")
                        .font(.subheadline)
                    Text(item.isEmbedded ? "Your AI assistant can use this information" : "Sync to enable AI to learn from this")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !item.isEmbedded {
                    Button("Sync") {
                        Task {
                            await ragService.embedProfileItem(item)
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
    
    // MARK: - Helpers
    private var typeColor: Color {
        switch itemType.color {
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
    
    private func proficiencyLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Beginner"
        case 2: return "Elementary"
        case 3: return "Intermediate"
        case 4: return "Advanced"
        case 5: return "Expert"
        default: return "Unknown"
        }
    }
    
    private func deleteItem() {
        // Drop the embedding first, or the assistant keeps citing deleted items.
        Task { await RAGService.shared.deleteProfileItem(item) }
        modelContext.delete(item)
        dismiss()
    }
}

#Preview {
    ProfileItemEditorView(item: nil, defaultType: .skill)
        .modelContainer(for: [ProfileItem.self], inMemory: true)
}
