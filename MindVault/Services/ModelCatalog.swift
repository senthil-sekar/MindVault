//
//  ModelCatalog.swift
//  MindVault
//
//  Curated list of MLX 4-bit models for iPhone 16 Plus (A18, 8 GB RAM)
//  and a download manager that streams them from HuggingFace.
//

import Foundation
import SwiftUI

// MARK: - Catalog Model

struct CatalogModel: Identifiable, Sendable {
    let id: String            // HuggingFace repo ID, e.g. "mlx-community/Llama-3.2-3B-Instruct-4bit"
    let displayName: String
    let family: String
    let parameters: String    // "1B", "3.8B", "7B"
    let approxSizeGB: Double  // approximate download size
    let description: String
    let tier: Tier
    let isRecommended: Bool

    enum Tier: String, CaseIterable, Sendable {
        case fast     = "Fast"
        case balanced = "Balanced"
        case quality  = "Quality"

        var tintColor: Color {
            switch self {
            case .fast:     return .green
            case .balanced: return .blue
            case .quality:  return .purple
            }
        }
        var systemImage: String {
            switch self {
            case .fast:     return "hare.fill"
            case .balanced: return "dial.medium.fill"
            case .quality:  return "star.fill"
            }
        }
    }

    var folderName: String {
        id.components(separatedBy: "/").last ?? id
    }

    var sizeString: String {
        approxSizeGB >= 1
            ? String(format: "%.1f GB", approxSizeGB)
            : String(format: "%.0f MB", approxSizeGB * 1000)
    }

    var hfAPIURL: URL {
        URL(string: "https://huggingface.co/api/models/\(id)?blobs=true")!
    }

    func resolveURL(for filename: String) -> URL {
        URL(string: "https://huggingface.co/\(id)/resolve/main/\(filename)")!
    }

    var localDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    var isInstalled: Bool {
        let fm = FileManager.default
        let dir = localDirectory
        guard fm.fileExists(atPath: dir.path) else { return false }
        let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.contains("config.json") && files.contains { $0.hasSuffix(".safetensors") }
    }
}

// MARK: - Catalog
// All models are 4-bit quantized MLX format from mlx-community on HuggingFace.
// Tested size range fits comfortably within iPhone 16 Plus 8 GB unified memory.

enum ModelCatalog {
    static let models: [CatalogModel] = [
        CatalogModel(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B",
            family: "Llama",
            parameters: "1B",
            approxSizeGB: 0.7,
            description: "Fastest option. Great for quick Q&A, tagging, and simple summaries.",
            tier: .fast,
            isRecommended: false
        ),
        CatalogModel(
            id: "mlx-community/gemma-3-1b-it-4bit",
            displayName: "Gemma 3 1B",
            family: "Gemma",
            parameters: "1B",
            approxSizeGB: 0.8,
            description: "Google's compact 1B instruction model. Fast with good quality.",
            tier: .fast,
            isRecommended: false
        ),
        CatalogModel(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B",
            family: "Llama",
            parameters: "3B",
            approxSizeGB: 1.8,
            description: "Best speed-quality balance. Ideal for journal reflection and RAG queries.",
            tier: .balanced,
            isRecommended: true
        ),
        CatalogModel(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            displayName: "Phi 3.5 Mini",
            family: "Phi",
            parameters: "3.8B",
            approxSizeGB: 2.2,
            description: "Microsoft's efficient model. Exceptional reasoning capability per GB.",
            tier: .balanced,
            isRecommended: false
        ),
        CatalogModel(
            id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            displayName: "Qwen 2.5 3B",
            family: "Qwen",
            parameters: "3B",
            approxSizeGB: 1.9,
            description: "Alibaba's multilingual 3B model. Strong structured reasoning.",
            tier: .balanced,
            isRecommended: false
        ),
        CatalogModel(
            id: "mlx-community/gemma-3-4b-it-4bit",
            displayName: "Gemma 3 4B",
            family: "Gemma",
            parameters: "4B",
            approxSizeGB: 2.5,
            description: "Google's capable 4B model. High quality outputs across diverse topics.",
            tier: .balanced,
            isRecommended: false
        ),
        CatalogModel(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            displayName: "Mistral 7B",
            family: "Mistral",
            parameters: "7B",
            approxSizeGB: 4.1,
            description: "Highest quality on-device option. Needs ~5 GB free RAM.",
            tier: .quality,
            isRecommended: false
        ),
    ]
}

// MARK: - Download Manager

// File-scope so the nonisolated download code can reach them without hopping
// to the main actor (static members of a @MainActor type are actor-isolated).

private let keepExtensions: Set<String> = ["json", "safetensors", "model", "tiktoken"]

private struct HFSibling: Decodable {
    let rfilename: String
    let size: Int64?
}

private struct HFModelInfo: Decodable {
    let siblings: [HFSibling]
}

/// Reports byte-level progress for a single file download. URLSession streams
/// straight to disk, so there's no per-byte work on our side.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onWrite: @Sendable (Int64, Int64) -> Void

    init(onWrite: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onWrite = onWrite
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onWrite(totalBytesWritten, totalBytesExpectedToWrite)
    }

    // The async download(from:delegate:) API takes ownership of the temp file,
    // so there's nothing to do here — but the protocol requires it.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

@MainActor
final class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()

    struct DownloadProgress: Sendable {
        var fileIndex: Int    = 0
        var totalFiles: Int   = 0
        var bytesDownloaded: Int64 = 0
        var totalBytes: Int64 = 0
        var currentFileName: String = ""

        var fraction: Double {
            guard totalBytes > 0 else {
                guard totalFiles > 0 else { return 0 }
                return Double(fileIndex) / Double(totalFiles)
            }
            return min(Double(bytesDownloaded) / Double(totalBytes), 1.0)
        }

        var statusText: String {
            guard totalBytes > 0 else { return "File \(fileIndex) of \(totalFiles)…" }
            let dl  = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
            let tot = ByteCountFormatter.string(fromByteCount: totalBytes,      countStyle: .file)
            return "\(dl) / \(tot)"
        }
    }

    @Published var activeDownloads: [String: DownloadProgress] = [:]
    @Published var downloadErrors:  [String: String]           = [:]

    /// Live download tasks, kept so cancellation actually cancels.
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Public

    func startDownload(for model: CatalogModel) {
        guard tasks[model.id] == nil else { return }
        activeDownloads[model.id] = DownloadProgress()
        downloadErrors.removeValue(forKey: model.id)

        let modelID = model.id
        tasks[modelID] = Task.detached(priority: .utility) { [weak self] in
            do {
                try await downloadModel(model) { progress in
                    await self?.applyProgress(id: modelID, progress: progress)
                }
                await self?.finalize(id: modelID, error: nil)
            } catch is CancellationError {
                await self?.finalize(id: modelID, error: nil)
            } catch {
                await self?.finalize(id: modelID, error: error)
            }
        }
    }

    func cancelDownload(for model: CatalogModel) {
        tasks[model.id]?.cancel()
        tasks.removeValue(forKey: model.id)
        activeDownloads.removeValue(forKey: model.id)
    }

    func uninstall(_ model: CatalogModel) throws {
        cancelDownload(for: model)
        try FileManager.default.removeItem(at: model.localDirectory)
    }

    // MARK: - Private

    private func applyProgress(id: String, progress: DownloadProgress) {
        guard activeDownloads[id] != nil else { return }  // cancelled while in flight
        activeDownloads[id] = progress
    }

    private func finalize(id: String, error: Error?) {
        activeDownloads.removeValue(forKey: id)
        tasks.removeValue(forKey: id)
        if let error { downloadErrors[id] = error.localizedDescription }
    }
}

// MARK: - Download implementation (nonisolated — never touches the main actor)

/// Downloads every weight/config file for `model` into its Documents folder.
/// Resumable: files already present at their expected size are skipped.
private func downloadModel(
    _ model: CatalogModel,
    onProgress: @escaping @Sendable (ModelDownloadManager.DownloadProgress) async -> Void
) async throws {
    // 1. File list (blobs=true gives per-file sizes)
    let (listData, _) = try await URLSession.shared.data(from: model.hfAPIURL)
    let info = try JSONDecoder().decode(HFModelInfo.self, from: listData)

    let files = info.siblings.filter { s in
        let ext = URL(fileURLWithPath: s.rfilename).pathExtension.lowercased()
        return keepExtensions.contains(ext) && !s.rfilename.lowercased().contains("readme")
    }
    guard !files.isEmpty else { throw URLError(.cannotParseResponse) }

    let totalBytes = files.compactMap(\.size).reduce(0, +)
    let fileCount = files.count

    let fm = FileManager.default
    try fm.createDirectory(at: model.localDirectory, withIntermediateDirectories: true)

    await onProgress(.init(totalFiles: fileCount, totalBytes: totalBytes))

    // Bytes from files already finished. Only mutated between files, never
    // from inside the progress closure.
    var completedBytes: Int64 = 0

    for (index, sibling) in files.enumerated() {
        try Task.checkCancellation()

        let fileIndex = index + 1
        let fileName = URL(fileURLWithPath: sibling.rfilename).lastPathComponent
        let base = completedBytes

        await onProgress(.init(
            fileIndex: fileIndex, totalFiles: fileCount,
            bytesDownloaded: base, totalBytes: totalBytes, currentFileName: fileName
        ))

        // Preserve any subdirectory structure inside the model folder
        let relDir = URL(fileURLWithPath: sibling.rfilename).deletingLastPathComponent().relativePath
        let dstDir = relDir == "."
            ? model.localDirectory
            : model.localDirectory.appendingPathComponent(relDir, isDirectory: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let dst = model.localDirectory.appendingPathComponent(sibling.rfilename)

        // Resume: only skip a file whose size matches what the Hub reports.
        // A truncated file from an interrupted run must be re-fetched, or the
        // model loads as corrupt much later with a confusing error.
        if let onDisk = (try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) {
            if let expected = sibling.size, onDisk == expected {
                completedBytes += onDisk
                await onProgress(.init(
                    fileIndex: fileIndex, totalFiles: fileCount,
                    bytesDownloaded: completedBytes, totalBytes: totalBytes,
                    currentFileName: fileName
                ))
                continue
            }
            try? fm.removeItem(at: dst)   // truncated or unknown size — refetch
        }

        // The delegate closure captures only immutable values.
        let delegate = DownloadProgressDelegate { written, _ in
            Task {
                await onProgress(.init(
                    fileIndex: fileIndex, totalFiles: fileCount,
                    bytesDownloaded: base + written, totalBytes: totalBytes,
                    currentFileName: fileName
                ))
            }
        }

        let (tempURL, response) = try await URLSession.shared.download(
            from: model.resolveURL(for: sibling.rfilename),
            delegate: delegate
        )

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            try? fm.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }

        try? fm.removeItem(at: dst)
        try fm.moveItem(at: tempURL, to: dst)

        let written = (try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            ?? sibling.size ?? 0
        completedBytes += written
    }
}
