//
//  EmailMessage.swift
//  MindVault
//
//  Created with AI assistance
//

import Foundation
import SwiftData

@Model
final class EmailMessage {
    var id: UUID
    var messageId: String // Provider's message ID
    var threadId: String?
    var subject: String
    var from: String
    var fromName: String?
    var to: [String]
    var cc: [String]?
    var bcc: [String]?
    var body: String
    var bodySnippet: String?
    var isHTML: Bool
    var date: Date
    var isRead: Bool
    var isStarred: Bool
    var labels: [String]?
    var hasAttachments: Bool
    var attachmentCount: Int
    var createdAt: Date
    var convertedToJournal: Bool
    var journalEntryId: UUID?
    var isProcessedForAI: Bool
    
    var account: EmailAccount?
    
    init(
        id: UUID = UUID(),
        messageId: String,
        threadId: String? = nil,
        subject: String,
        from: String,
        fromName: String? = nil,
        to: [String],
        cc: [String]? = nil,
        bcc: [String]? = nil,
        body: String,
        bodySnippet: String? = nil,
        isHTML: Bool = false,
        date: Date,
        isRead: Bool = false,
        isStarred: Bool = false,
        labels: [String]? = nil,
        hasAttachments: Bool = false,
        attachmentCount: Int = 0,
        createdAt: Date = Date(),
        convertedToJournal: Bool = false,
        journalEntryId: UUID? = nil,
        isProcessedForAI: Bool = false
    ) {
        self.id = id
        self.messageId = messageId
        self.threadId = threadId
        self.subject = subject
        self.from = from
        self.fromName = fromName
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.body = body
        self.bodySnippet = bodySnippet
        self.isHTML = isHTML
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.labels = labels
        self.hasAttachments = hasAttachments
        self.attachmentCount = attachmentCount
        self.createdAt = createdAt
        self.convertedToJournal = convertedToJournal
        self.journalEntryId = journalEntryId
        self.isProcessedForAI = isProcessedForAI
    }
}
