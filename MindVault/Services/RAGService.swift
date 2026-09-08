//
//  RAGService.swift
//  MindVault
//
//  Retrieval-Augmented Generation service
//  Orchestrates embedding, search, and LLM for answering questions
//  Uses backend API for all RAG operations

import Foundation
import SwiftData

@MainActor
class RAGService: ObservableObject {
    static let shared = RAGService()
    
    @Published var isProcessing = false
    @Published var processingStatus: String = ""
    @Published var lastError: String?
    
    private let apiClient = APIClient.shared
    
    private init() {}
    
    // MARK: - Embed Journal Entry
    func embedJournalEntry(_ entry: JournalEntry) async {
        isProcessing = true
        processingStatus = "Processing journal entry..."
        
        do {
            // Send to backend for embedding and storage
            let upsertRequest = UpsertRequest(
                id: entry.id.uuidString,
                content: entry.fullText,
                metadata: entry.metadata
            )
            
            try await apiClient.upsert(request: upsertRequest)
            
            entry.isEmbedded = true
            entry.embeddingId = entry.id.uuidString
            
            processingStatus = "Entry synced to AI"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            processingStatus = "Failed to sync entry"
        }
        
        isProcessing = false
    }
    
    // MARK: - Embed Profile Item
    func embedProfileItem(_ item: ProfileItem) async {
        isProcessing = true
        processingStatus = "Processing profile item..."
        
        do {
            // Send to backend for embedding and storage
            let upsertRequest = UpsertRequest(
                id: item.id.uuidString,
                content: item.fullText,
                metadata: item.metadata
            )
            
            try await apiClient.upsert(request: upsertRequest)
            
            item.isEmbedded = true
            item.embeddingId = item.id.uuidString
            
            processingStatus = "Profile item synced to AI"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            processingStatus = "Failed to sync profile item"
        }
        
        isProcessing = false
    }
    
    // MARK: - Generate Response with RAG
    func generateResponse(to query: String) async -> (String, [ChatContext]) {
        isProcessing = true
        processingStatus = "Searching your journal..."

        do {
            let mode = Configuration.llmMode

            if mode == .backend {
                // Backend handles embedding + search + generation end-to-end
                let chatRequest = ChatRequest(message: query)
                let response = try await apiClient.chat(request: chatRequest)
                let contexts = response.contexts.map { result in
                    ChatContext(
                        documentId: result.id,
                        documentType: result.type,
                        title: result.title,
                        snippet: result.snippet,
                        relevanceScore: Float(result.score),
                        date: nil
                    )
                }
                lastError = nil
                isProcessing = false
                return (response.response, contexts)
            } else {
                // BYOK / Local: backend handles search; selected provider handles generation
                processingStatus = "Retrieving relevant context..."
                let results = try await apiClient.search(query: query, topK: Configuration.RAG.topK)

                let contexts: [ChatContext] = results.compactMap { result in
                    guard let content = result.content else { return nil }
                    let meta = result.metadata
                    let title = (meta["title"]?.value as? String)
                        ?? (meta["subject"]?.value as? String)
                        ?? "Result"
                    let type = (meta["type"]?.value as? String) ?? "document"
                    return ChatContext(
                        documentId: result.id,
                        documentType: type,
                        title: title,
                        snippet: String(content.prefix(300)),
                        relevanceScore: result.score,
                        date: nil
                    )
                }

                processingStatus = "Generating response..."
                let contextTexts = results.compactMap { $0.content }
                let userMessage = buildRAGMessage(contexts: contextTexts, query: query)
                let answer = try await LLMService.activeProvider.complete(
                    systemPrompt: Configuration.LLM.systemPrompt,
                    userMessage: userMessage,
                    history: []
                )

                lastError = nil
                isProcessing = false
                return (answer, contexts)
            }
        } catch {
            lastError = error.localizedDescription
            isProcessing = false
            return ("I'm having trouble connecting to the AI service. Please check your settings and try again.", [])
        }
    }

    private func buildRAGMessage(contexts: [String], query: String) -> String {
        var msg = "Here is relevant information from the user's personal journal and profile:\n\n"
        for (i, ctx) in contexts.enumerated() {
            msg += "--- Context \(i + 1) ---\n\(ctx)\n\n"
        }
        msg += "---\n\nUser Question: \(query)"
        return msg
    }
    
    // MARK: - Batch Sync
    func syncAllEntries(entries: [JournalEntry], items: [ProfileItem]) async -> (success: Int, failed: Int) {
        isProcessing = true
        var successCount = 0
        var failedCount = 0
        
        let totalCount = entries.count + items.count
        var currentIndex = 0
        
        // Sync journal entries
        for entry in entries where !entry.isEmbedded {
            currentIndex += 1
            processingStatus = "Syncing \(currentIndex)/\(totalCount)..."
            
            do {
                let upsertRequest = UpsertRequest(
                    id: entry.id.uuidString,
                    content: entry.fullText,
                    metadata: entry.metadata
                )
                try await apiClient.upsert(request: upsertRequest)
                
                entry.isEmbedded = true
                entry.embeddingId = entry.id.uuidString
                successCount += 1
            } catch {
                failedCount += 1
            }
        }
        
        // Sync profile items
        for item in items where !item.isEmbedded {
            currentIndex += 1
            processingStatus = "Syncing \(currentIndex)/\(totalCount)..."
            
            do {
                let upsertRequest = UpsertRequest(
                    id: item.id.uuidString,
                    content: item.fullText,
                    metadata: item.metadata
                )
                try await apiClient.upsert(request: upsertRequest)
                
                item.isEmbedded = true
                item.embeddingId = item.id.uuidString
                successCount += 1
            } catch {
                failedCount += 1
            }
        }
        
        processingStatus = "Sync complete"
        isProcessing = false
        return (successCount, failedCount)
    }
    
    // MARK: - Delete from Vector DB
    func deleteEntry(_ entry: JournalEntry) async {
        guard let embeddingId = entry.embeddingId else { return }
        
        do {
            let deleteRequest = DeleteRequest(id: embeddingId)
            try await apiClient.delete(request: deleteRequest)
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    func deleteProfileItem(_ item: ProfileItem) async {
        guard let embeddingId = item.embeddingId else { return }
        
        do {
            let deleteRequest = DeleteRequest(id: embeddingId)
            try await apiClient.delete(request: deleteRequest)
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    // MARK: - Insights Generation
    func generateInsights(from entries: [JournalEntry]) async -> String? {
        guard !entries.isEmpty else { return nil }
        
        isProcessing = true
        processingStatus = "Analyzing your journal..."
        
        let recentEntries = entries.prefix(20).map { $0.fullText }.joined(separator: "\n\n---\n\n")
        let prompt = """
        Based on these recent journal entries, provide 3-5 key insights about patterns, growth, or themes you notice. Be specific and actionable.
        
        Journal Entries:
        \(recentEntries)
        """
        
        do {
            let response: String
            if Configuration.llmMode == .backend {
                let chatRequest = ChatRequest(message: prompt)
                response = try await apiClient.chat(request: chatRequest).response
            } else {
                response = try await LLMService.activeProvider.complete(
                    systemPrompt: Configuration.LLM.systemPrompt,
                    userMessage: prompt,
                    history: []
                )
            }
            isProcessing = false
            return response
        } catch {
            lastError = error.localizedDescription
            isProcessing = false
            return nil
        }
    }
}
