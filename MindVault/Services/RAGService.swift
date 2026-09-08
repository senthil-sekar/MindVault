//
//  RAGService.swift
//  MindVault
//
//  Retrieval-Augmented Generation service.
//  Retrieval (embedding + vector search) always runs on-device — MindVault has
//  no backend to call. Generation is the only thing that varies by AI Mode:
//  MLX on-device, or OpenAI via BYOK, chosen through LLMService.activeProvider.

import Foundation
import SwiftData

@MainActor
class RAGService: ObservableObject {
    static let shared = RAGService()

    @Published var isProcessing = false
    @Published var processingStatus: String = ""
    @Published var lastError: String?

    private init() {}

    // MARK: - Embed Journal Entry
    func embedJournalEntry(_ entry: JournalEntry) async {
        isProcessing = true
        processingStatus = "Processing journal entry..."

        do {
            let vector = try EmbeddingService.embedLocally(entry.fullText)
            LocalVectorStore.shared.upsert(LocalVectorStore.VectorDocument(
                id: entry.id.uuidString,
                type: "journal_entry",
                title: entry.title,
                content: entry.fullText,
                vector: vector,
                indexedAt: Date()
            ))

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
            let vector = try EmbeddingService.embedLocally(item.fullText)
            LocalVectorStore.shared.upsert(LocalVectorStore.VectorDocument(
                id: item.id.uuidString,
                type: item.type,
                title: item.title,
                content: item.fullText,
                vector: vector,
                indexedAt: Date()
            ))

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
        processingStatus = "Embedding query on-device..."

        do {
            let queryVector = try EmbeddingService.embedLocally(query)

            processingStatus = "Searching your journal..."
            let matches = LocalVectorStore.shared.search(
                queryVector: queryVector,
                topK: Configuration.RAG.topK
            )

            let contexts = matches.map { match in
                ChatContext(
                    documentId: match.id,
                    documentType: match.type,
                    title: match.title,
                    snippet: String(match.content.prefix(300)),
                    relevanceScore: match.score,
                    date: nil
                )
            }

            processingStatus = "Generating response..."
            let contextTexts = matches.map { $0.content }
            let answer = try await LLMService.activeProvider.complete(
                systemPrompt: Configuration.LLM.systemPrompt,
                userMessage: buildRAGMessage(contexts: contextTexts, query: query),
                history: []
            )
            lastError = nil
            isProcessing = false
            return (answer, contexts)
        } catch {
            lastError = error.localizedDescription
            isProcessing = false
            return ("I'm having trouble generating a response. Please check your settings and try again.", [])
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

        let unsyncedEntries = entries.filter { !$0.isEmbedded }
        let unsyncedItems   = items.filter   { !$0.isEmbedded }
        let total = unsyncedEntries.count + unsyncedItems.count
        var current = 0

        for entry in unsyncedEntries {
            current += 1
            processingStatus = "Syncing \(current)/\(total)…"
            await embedJournalEntry(entry)
            entry.isEmbedded ? (successCount += 1) : (failedCount += 1)
        }

        for item in unsyncedItems {
            current += 1
            processingStatus = "Syncing \(current)/\(total)…"
            await embedProfileItem(item)
            item.isEmbedded ? (successCount += 1) : (failedCount += 1)
        }

        processingStatus = "Sync complete"
        isProcessing = false
        return (successCount, failedCount)
    }

    // MARK: - Delete from Vector Store
    func deleteEntry(_ entry: JournalEntry) async {
        guard let embeddingId = entry.embeddingId else { return }
        LocalVectorStore.shared.delete(id: embeddingId)
    }

    func deleteProfileItem(_ item: ProfileItem) async {
        guard let embeddingId = item.embeddingId else { return }
        LocalVectorStore.shared.delete(id: embeddingId)
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
            let response = try await LLMService.activeProvider.complete(
                systemPrompt: Configuration.LLM.systemPrompt,
                userMessage: prompt,
                history: []
            )
            isProcessing = false
            return response
        } catch {
            lastError = error.localizedDescription
            isProcessing = false
            return nil
        }
    }
}
