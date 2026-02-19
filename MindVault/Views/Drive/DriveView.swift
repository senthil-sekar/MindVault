//
//  DriveView.swift
//  MindVault
//
//  Google Drive browser and document sync view
//

import SwiftUI
import SwiftData

struct DriveView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var driveService = DriveService.shared
    
    @State private var selectedFiles: Set<String> = []
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var navigationPath: [DriveFolder] = []
    @State private var processingProgress: (current: Int, total: Int) = (0, 0)
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !driveService.isAuthenticated {
                    notConnectedView
                } else if driveService.isLoading && driveService.files.isEmpty {
                    loadingView
                } else {
                    fileListView
                }
            }
            .navigationTitle("Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if driveService.isAuthenticated {
                            Button {
                                Task { await refreshFiles() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            
                            Button {
                                Task { await syncSelectedFiles() }
                            } label: {
                                Label("Sync Selected (\(selectedFiles.count))", systemImage: "arrow.down.doc")
                            }
                            .disabled(selectedFiles.isEmpty)
                            
                            Button {
                                Task { await syncAllSupported() }
                            } label: {
                                Label("Sync All Documents", systemImage: "arrow.down.doc.fill")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                driveService.disconnect()
                            } label: {
                                Label("Disconnect", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: DriveFolder.self) { folder in
                DriveSubfolderView(folder: folder, driveService: driveService)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            if driveService.isAuthenticated && driveService.files.isEmpty {
                await refreshFiles()
            }
        }
    }
    
    // MARK: - Views
    
    private var notConnectedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 80))
                .foregroundStyle(.indigo.gradient)
            
            VStack(spacing: 8) {
                Text("Connect Google Drive")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Access your documents, PDFs, and files to enhance your AI assistant's knowledge.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button {
                Task {
                    do {
                        try await driveService.authenticate()
                        await refreshFiles()
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Connect to Google Drive")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            
            // Supported file types
            VStack(alignment: .leading, spacing: 12) {
                Text("Supported Files")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    fileTypeLabel(icon: "doc.fill", name: "PDF")
                    fileTypeLabel(icon: "doc.text.fill", name: "Word")
                    fileTypeLabel(icon: "doc.plaintext.fill", name: "Text")
                }
            }
            .padding(.top, 20)
        }
        .padding()
    }
    
    private func fileTypeLabel(icon: String, name: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.indigo)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 60)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading files...")
                .foregroundStyle(.secondary)
        }
    }
    
    private var fileListView: some View {
        List(selection: $selectedFiles) {
            // Status section
            if !driveService.syncStatus.isEmpty || isProcessing {
                Section {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(driveService.syncStatus)
                                .font(.subheadline)
                            
                            if processingProgress.total > 0 {
                                Text("\(processingProgress.current)/\(processingProgress.total) files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Folders section
            let folders = driveService.files.filter { $0.isFolder }
            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders) { folder in
                        NavigationLink(value: DriveFolder(id: folder.id, name: folder.name, parentId: "root")) {
                            FileRow(file: folder, isSelected: false)
                        }
                    }
                }
            }
            
            // Files section
            let files = driveService.files.filter { !$0.isFolder }
            if !files.isEmpty {
                Section("Files") {
                    ForEach(files) { file in
                        FileRow(file: file, isSelected: selectedFiles.contains(file.id))
                            .onTapGesture {
                                toggleSelection(file.id)
                            }
                    }
                }
            }
            
            if driveService.files.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "doc",
                    description: Text("This folder is empty")
                )
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refreshFiles()
        }
    }
    
    // MARK: - Functions
    
    private func toggleSelection(_ id: String) {
        if selectedFiles.contains(id) {
            selectedFiles.remove(id)
        } else {
            selectedFiles.insert(id)
        }
    }
    
    private func refreshFiles() async {
        do {
            _ = try await driveService.listFiles(folderId: "root")
        } catch DriveError.notAuthenticated {
            // Token is invalid, disconnect and require re-auth
            driveService.disconnect()
        } catch DriveError.authenticationFailed(let message) {
            // Auth failed, might need to reconnect
            if message.contains("401") || message.contains("invalid") || message.contains("expired") {
                driveService.disconnect()
            } else {
                errorMessage = message
                showingError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func syncSelectedFiles() async {
        isProcessing = true
        processingProgress = (0, selectedFiles.count)
        
        for fileId in selectedFiles {
            if let file = driveService.files.first(where: { $0.id == fileId && $0.isSupported }) {
                do {
                    _ = try await driveService.processDocumentForRAG(
                        fileId: file.id,
                        filename: file.name,
                        mimeType: file.mimeType
                    )
                    processingProgress.current += 1
                } catch {
                    print("❌ Failed to process \(file.name): \(error)")
                }
            }
        }
        
        selectedFiles.removeAll()
        isProcessing = false
    }
    
    private func syncAllSupported() async {
        isProcessing = true
        let supportedFiles = driveService.files.filter { $0.isSupported }
        processingProgress = (0, supportedFiles.count)
        
        for file in supportedFiles {
            do {
                _ = try await driveService.processDocumentForRAG(
                    fileId: file.id,
                    filename: file.name,
                    mimeType: file.mimeType
                )
                processingProgress.current += 1
            } catch {
                print("❌ Failed to process \(file.name): \(error)")
            }
        }
        
        isProcessing = false
    }
}

// MARK: - File Row

struct FileRow: View {
    let file: DriveFileItem
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            if !file.isFolder {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .indigo : .secondary)
            }
            
            // File icon
            Image(systemName: file.iconName)
                .font(.title2)
                .foregroundStyle(file.isFolder ? .yellow : .indigo)
                .frame(width: 32)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if !file.isFolder {
                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(file.modifiedTime, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Status indicator
            if !file.isSupported && !file.isFolder {
                Text("Unsupported")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Subfolder View

struct DriveSubfolderView: View {
    let folder: DriveFolder
    @ObservedObject var driveService: DriveService
    
    @State private var files: [DriveFileItem] = []
    @State private var isLoading = true
    @State private var selectedFiles: Set<String> = []
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else {
                List {
                    // Folders
                    let folders = files.filter { $0.isFolder }
                    if !folders.isEmpty {
                        Section("Folders") {
                            ForEach(folders) { subfolder in
                                NavigationLink(value: DriveFolder(id: subfolder.id, name: subfolder.name, parentId: folder.id)) {
                                    FileRow(file: subfolder, isSelected: false)
                                }
                            }
                        }
                    }
                    
                    // Files
                    let documents = files.filter { !$0.isFolder }
                    if !documents.isEmpty {
                        Section("Files") {
                            ForEach(documents) { file in
                                FileRow(file: file, isSelected: selectedFiles.contains(file.id))
                                    .onTapGesture {
                                        if selectedFiles.contains(file.id) {
                                            selectedFiles.remove(file.id)
                                        } else {
                                            selectedFiles.insert(file.id)
                                        }
                                    }
                            }
                        }
                    }
                    
                    if files.isEmpty {
                        ContentUnavailableView(
                            "Empty Folder",
                            systemImage: "folder",
                            description: Text("This folder has no files")
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(folder.name)
        .task {
            do {
                files = try await driveService.listFiles(folderId: folder.id)
                isLoading = false
            } catch {
                isLoading = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await syncSelected()
                    }
                } label: {
                    Label("Sync (\(selectedFiles.count))", systemImage: "arrow.down.doc")
                }
                .disabled(selectedFiles.isEmpty)
            }
        }
    }
    
    private func syncSelected() async {
        for fileId in selectedFiles {
            if let file = files.first(where: { $0.id == fileId && $0.isSupported }) {
                do {
                    _ = try await driveService.processDocumentForRAG(
                        fileId: file.id,
                        filename: file.name,
                        mimeType: file.mimeType
                    )
                } catch {
                    print("❌ Failed: \(error)")
                }
            }
        }
        selectedFiles.removeAll()
    }
}

#Preview {
    DriveView()
}
