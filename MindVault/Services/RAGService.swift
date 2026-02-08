//
//  RAGService.swift
//  MindVault
//
//  Retrieval-Augmented Generation service
//  Orchestrates embedding, search, and LLM for answering questions
//

import Foundation
import SwiftData

@MainActor
class RAGService: ObservableObject {
    static let shared = RAGService()
    
    @Published var isProcessing = false
    @Published var processingStatus: String = ""
    @Published var lastError: String?
    
    private let embeddingService = EmbeddingService.shared
    private let vectorDBService = VectorDBService.shared
    private let llmService = LLMService.shared
    private let apiClient = APIClient.shared
    
    private init() {}
    
    // MARK: - Embed Journal Entry
    func embedJournalEntry(_ entry: JournalEntry) async {
        isProcessing = true
        processingStatus = "Processing journal entry..."
        
        do {
            let content = embeddingService.prepareText(entry.fullText)
            
            try await vectorDBService.upsert(
                id: entry.id.uuidString,
                content: content,
                type: VectorDBService.DocumentType.journalEntry.rawValue,
                metadata: entry.metadata
            )
            
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
            let content = embeddingService.prepareText(item.fullText)
            
            try await vectorDBService.upsert(
                id: item.id.uuidString,
                content: content,
                type: VectorDBService.DocumentType.profileItem.rawValue,
                metadata: item.metadata
            )
            
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
            // 1. Search for relevant documents
            let searchResults = try await vectorDBService.search(query: query)
            
            // 2. Extract context from results
            var contexts: [ChatContext] = []
            var contextTexts: [String] = []
            
            for result in searchResults {
                let docType = (result.metadata["type"]?.value as? String) ?? "unknown"
                let title = (result.metadata["title"]?.value as? String) ?? "Untitled"
                let content = result.content ?? ""
                
                let chatContext = ChatContext(
                    documentId: result.id,
                    documentType: docType,
                    title: title,
                    snippet: String(content.prefix(300)),
                    relevanceScore: result.score,
                    date: nil
                )
                contexts.append(chatContext)
                contextTexts.append(content)
            }
            
            processingStatus = "Generating response..."
            
            // 3. Generate response using LLM
            let response: String
            if contextTexts.isEmpty {
                response = "I don't have enough information in your journal to answer that question. Try adding more entries about this topic, or rephrase your question."
            } else {
                let chatResponse = try await apiClient.chat(message: query)
                response = chatResponse.response
            }
            
            lastError = nil
            isProcessing = false
            return (response, contexts)
            
        } catch {
            lastError = error.localizedDescription
            isProcessing = false
            return ("I'm having trouble connecting to the AI service. Please check your connection and try again.", [])
        }
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
                let content = embeddingService.prepareText(entry.fullText)
                try await vectorDBService.upsert(
                    id: entry.id.uuidString,
                    content: content,
                    type: VectorDBService.DocumentType.journalEntry.rawValue,
                    metadata: entry.metadata
                )
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
                let content = embeddingService.prepareText(item.fullText)
                try await vectorDBService.upsert(
                    id: item.id.uuidString,
                    content: content,
                    type: VectorDBService.DocumentType.profileItem.rawValue,
                    metadata: item.metadata
                )
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
            try await vectorDBService.delete(id: embeddingId)
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    func deleteProfileItem(_ item: ProfileItem) async {
        guard let embeddingId = item.embeddingId else { return }
        
        do {
            try await vectorDBService.delete(id: embeddingId)
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
            let response = try await apiClient.chat(message: prompt)
            isProcessing = false
            return response.response
        } catch {
            lastError = error.localizedDescription
            isProcessing = false
            return nil
        }
    }
}
