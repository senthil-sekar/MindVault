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

    private init() {}

    // MARK: - Public

    func startDownload(for model: CatalogModel) {
        guard activeDownloads[model.id] == nil else { return }
        activeDownloads[model.id] = DownloadProgress()
        downloadErrors.removeValue(forKey: model.id)

        let modelID = model.id
        Task.detached(priority: .utility) { [weak self] in
            do {
                try await Self.performDownload(model: model) { progress in
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
        activeDownloads.removeValue(forKey: model.id)
    }

    func uninstall(_ model: CatalogModel) throws {
        try FileManager.default.removeItem(at: model.localDirectory)
    }

    // MARK: - Private

    private func applyProgress(id: String, progress: DownloadProgress) {
        guard activeDownloads[id] != nil else { return }  // cancelled while in flight
        activeDownloads[id] = progress
    }

    private func finalize(id: String, error: Error?) {
        activeDownloads.removeValue(forKey: id)
        if let error { downloadErrors[id] = error.localizedDescription }
    }

    // MARK: - Static Download Logic  (runs off main actor)

    private struct HFSibling: Decodable {
        let rfilename: String
        let size: Int64?
    }
    private struct HFModelInfo: Decodable {
        let siblings: [HFSibling]
    }

    private static let keepExtensions: Set<String> = [
        "json", "safetensors", "model", "tiktoken"
    ]

    static func performDownload(
        model: CatalogModel,
        onProgress: @Sendable (DownloadProgress) async -> Void
    ) async throws {
        // 1. Fetch file list (blobs=true adds per-file sizes)
        let (listData, _) = try await URLSession.shared.data(from: model.hfAPIURL)
        let info = try JSONDecoder().decode(HFModelInfo.self, from: listData)

        let files = info.siblings.filter { s in
            let ext = URL(fileURLWithPath: s.rfilename).pathExtension.lowercased()
            return keepExtensions.contains(ext) && !s.rfilename.lowercased().contains("readme")
        }
        guard !files.isEmpty else { throw URLError(.cannotParseResponse) }

        let totalBytes: Int64 = files.compactMap(\.size).reduce(0, +)

        // 2. Destination directory
        let fm = FileManager.default
        try fm.createDirectory(at: model.localDirectory, withIntermediateDirectories: true)

        await onProgress(DownloadProgress(totalFiles: files.count, totalBytes: totalBytes))

        // Bytes from files already finished. Only mutated between files — never
        // from inside the progress closure, which would be a data race.
        var completedBytes: Int64 = 0

        // 3. Download each file
        for (index, sibling) in files.enumerated() {
            try Task.checkCancellation()

            let fileIndex = index + 1
            let fileName = URL(fileURLWithPath: sibling.rfilename).lastPathComponent
            let base = completedBytes          // immutable snapshot for this file
            let fileCount = files.count

            await onProgress(DownloadProgress(
                fileIndex: fileIndex, totalFiles: fileCount,
                bytesDownloaded: base, totalBytes: totalBytes,
                currentFileName: fileName
            ))

            // Preserve any subdirectory structure inside the model folder
            let relDir = URL(fileURLWithPath: sibling.rfilename)
                .deletingLastPathComponent().relativePath
            let dstDir = relDir == "."
                ? model.localDirectory
                : model.localDirectory.appendingPathComponent(relDir, isDirectory: true)
            try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
            let dst = model.localDirectory.appendingPathComponent(sibling.rfilename)

            if fm.fileExists(atPath: dst.path) {
                let existing = (try? dst.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .flatMap { Int64($0) } ?? sibling.size ?? 0
                completedBytes += existing
                await onProgress(DownloadProgress(
                    fileIndex: fileIndex, totalFiles: fileCount,
                    bytesDownloaded: completedBytes, totalBytes: totalBytes,
                    currentFileName: fileName
                ))
                continue
            }

            // The closure captures only immutable values, so there's nothing to race on.
            let written = try await streamToFile(
                from: model.resolveURL(for: sibling.rfilename),
                to: dst
            ) { bytesThisFile in
                await onProgress(DownloadProgress(
                    fileIndex: fileIndex, totalFiles: fileCount,
                    bytesDownloaded: base + bytesThisFile, totalBytes: totalBytes,
                    currentFileName: fileName
                ))
            }
            completedBytes += written
        }
    }

    /// Streams `url` to `destination`, reporting bytes written *for this file*.
    /// Returns the total written.
    private static func streamToFile(
        from url: URL,
        to destination: URL,
        onFileProgress: @Sendable (Int64) async -> Void
    ) async throws -> Int64 {
        let (asyncBytes, _) = try await URLSession.shared.bytes(from: url)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var written: Int64 = 0
        var chunk = Data(capacity: 512 * 1024)

        for try await byte in asyncBytes {
            chunk.append(byte)
            if chunk.count >= 512 * 1024 {
                try handle.write(contentsOf: chunk)
                written += Int64(chunk.count)
                chunk.removeAll(keepingCapacity: true)
                await onFileProgress(written)
            }
        }
        if !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
            written += Int64(chunk.count)
            await onFileProgress(written)
        }
        return written
    }
}
