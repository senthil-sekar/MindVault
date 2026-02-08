//
//  JournalEditorView.swift
//  MindVault
//
//  Editor view for creating/editing journal entries
//

import SwiftUI
import SwiftData
import Speech

struct JournalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let entry: JournalEntry?
    
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var category: Category = .personal
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @State private var mood: Mood?
    @State private var isFavorite: Bool = false
    
    @State private var isRecording = false
    @State private var showingVoiceInput = false
    @State private var speechRecognizer = SFSpeechRecognizer()
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    
    @State private var isSaving = false
    @StateObject private var ragService = RAGService.shared
    
    var isNewEntry: Bool { entry == nil }
    
    var body: some View {
        NavigationStack {
            Form {
                // Title Section
                Section {
                    TextField("Entry Title", text: $title)
                        .font(.headline)
                } header: {
                    Text("Title")
                }
                
                // Content Section
                Section {
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("What's on your mind?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        
                        TextEditor(text: $content)
                            .frame(minHeight: 200)
                    }
                    
                    HStack {
                        Spacer()
                        
                        Button {
                            showingVoiceInput.toggle()
                        } label: {
                            Label("Voice Input", systemImage: isRecording ? "mic.fill" : "mic")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(isRecording ? .red : .indigo)
                    }
                } header: {
                    Text("Content")
                }
                
                // Category Section
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                } header: {
                    Text("Category")
                }
                
                // Mood Section
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Mood.allCases, id: \.self) { m in
                                VStack(spacing: 4) {
                                    Text(m.emoji)
                                        .font(.title)
                                    Text(m.rawValue)
                                        .font(.caption2)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(mood == m ? Color.indigo.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(mood == m ? Color.indigo : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        mood = mood == m ? nil : m
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Mood (Optional)")
                }
                
                // Tags Section
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
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
                        TextField("Add tag", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        Button("Add") {
                            addTag()
                        }
                        .disabled(newTag.isEmpty)
                    }
                    
                    // Suggested Tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Text("Suggested:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(suggestedTags, id: \.self) { tag in
                                Button(tag) {
                                    if !tags.contains(tag) {
                                        tags.append(tag)
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } header: {
                    Text("Tags")
                }
                
                // Options Section
                Section {
                    Toggle("Add to Favorites", isOn: $isFavorite)
                    
                    Toggle("Sync to AI immediately", isOn: .constant(true))
                        .disabled(true)
                }
            }
            .navigationTitle(isNewEntry ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveEntry()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(content.isEmpty || isSaving)
                }
            }
            .onAppear {
                loadEntryData()
            }
            .sheet(isPresented: $showingVoiceInput) {
                VoiceInputSheet(
                    isRecording: $isRecording,
                    transcribedText: $content
                )
                .presentationDetents([.medium])
            }
        }
    }
    
    private var suggestedTags: [String] {
        let categoryTags: [Category: [String]] = [
            .personal: ["reflection", "thoughts", "daily", "life"],
            .work: ["meeting", "project", "deadline", "achievement"],
            .education: ["learning", "course", "study", "exam"],
            .skills: ["practice", "improvement", "new-skill", "mastery"],
            .memories: ["family", "friends", "travel", "celebration"],
            .goals: ["2024", "short-term", "long-term", "milestone"],
            .health: ["workout", "nutrition", "sleep", "mental-health"],
            .relationships: ["family", "friends", "partner", "networking"],
            .travel: ["adventure", "vacation", "exploration", "culture"],
            .creativity: ["art", "writing", "music", "ideas"],
            .finance: ["budget", "investment", "savings", "planning"],
            .reflection: ["gratitude", "lessons", "growth", "insights"]
        ]
        
        return (categoryTags[category] ?? ["general"]).filter { !tags.contains($0) }
    }
    
    private func loadEntryData() {
        if let entry = entry {
            title = entry.title
            content = entry.content
            category = Category(rawValue: entry.category) ?? .personal
            tags = entry.tags
            isFavorite = entry.isFavorite
            if let moodString = entry.mood {
                mood = Mood(rawValue: moodString)
            }
        }
    }
    
    private func addTag() {
        let cleanedTag = newTag.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        
        if !cleanedTag.isEmpty && !tags.contains(cleanedTag) {
            tags.append(cleanedTag)
        }
        newTag = ""
    }
    
    private func saveEntry() {
        isSaving = true
        
        if let entry = entry {
            // Update existing entry
            entry.title = title
            entry.content = content
            entry.category = category.rawValue
            entry.tags = tags
            entry.mood = mood?.rawValue
            entry.moodScore = mood?.score
            entry.isFavorite = isFavorite
            entry.updatedAt = Date()
            entry.isEmbedded = false  // Mark for re-embedding
        } else {
            // Create new entry
            let newEntry = JournalEntry(
                title: title,
                content: content,
                category: category.rawValue,
                tags: tags,
                isFavorite: isFavorite,
                mood: mood?.rawValue,
                moodScore: mood?.score
            )
            modelContext.insert(newEntry)
            
            // Trigger embedding
            Task {
                await ragService.embedJournalEntry(newEntry)
            }
        }
        
        isSaving = false
        dismiss()
    }
}

// MARK: - Voice Input Sheet
struct VoiceInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isRecording: Bool
    @Binding var transcribedText: String
    
    @State private var speechRecognizer: SFSpeechRecognizer?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    @State private var liveTranscript = ""
    @State private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Voice Input")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(liveTranscript.isEmpty ? "Tap the microphone to start speaking" : liveTranscript)
                .font(.body)
                .foregroundStyle(liveTranscript.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 100)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(isRecording ? .red : .indigo)
                    .symbolEffect(.pulse, isActive: isRecording)
            }
            
            Text(isRecording ? "Tap to stop" : "Tap to speak")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !liveTranscript.isEmpty {
                Button {
                    transcribedText += (transcribedText.isEmpty ? "" : "\n\n") + liveTranscript
                    liveTranscript = ""
                    dismiss()
                } label: {
                    Text("Add to Entry")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.indigo.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .onAppear {
            requestSpeechAuthorization()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                authorizationStatus = status
                speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            }
        }
    }
    
    private func startRecording() {
        guard authorizationStatus == .authorized,
              let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                liveTranscript = result.bestTranscription.formattedString
            }
            
            if error != nil || (result?.isFinal ?? false) {
                stopRecording()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("Audio engine error: \(error)")
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}

#Preview {
    JournalEditorView(entry: nil)
        .modelContainer(for: [JournalEntry.self], inMemory: true)
}
