//
//  ModelBrowserView.swift
//  MindVault
//
//  On-device model picker: browse, download, and select MLX models.
//

import SwiftUI

struct ModelBrowserView: View {
    @AppStorage("localModelPath") private var localModelPath = ""
    @ObservedObject private var downloadManager = ModelDownloadManager.shared

    @State private var tierFilter: CatalogModel.Tier? = nil
    @State private var modelToDelete: CatalogModel? = nil
    @State private var refreshToken = UUID()   // forces isInstalled re-evaluation

    private var visibleModels: [CatalogModel] {
        guard let filter = tierFilter else { return ModelCatalog.models }
        return ModelCatalog.models.filter { $0.tier == filter }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                deviceNote
                tierPicker
                    .padding(.bottom, 8)

                LazyVStack(spacing: 12) {
                    ForEach(visibleModels) { model in
                        ModelCard(
                            model: model,
                            isActive: localModelPath == model.localDirectory.path,
                            downloadProgress: downloadManager.activeDownloads[model.id],
                            downloadError: downloadManager.downloadErrors[model.id],
                            onDownload:  { downloadManager.startDownload(for: model) },
                            onCancel:    { downloadManager.cancelDownload(for: model) },
                            onSelect:    { localModelPath = model.localDirectory.path },
                            onDelete:    { modelToDelete = model }
                        )
                        .id(refreshToken)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("On-Device Models")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete \(modelToDelete?.displayName ?? "model")?",
            isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    try? downloadManager.uninstall(model)
                    if localModelPath == model.localDirectory.path { localModelPath = "" }
                    modelToDelete = nil
                    refreshToken = UUID()
                }
            }
            Button("Cancel", role: .cancel) { modelToDelete = nil }
        } message: {
            if let model = modelToDelete {
                Text("This will remove \(model.sizeString) from your device.")
            }
        }
    }

    // MARK: - Sub-views

    private var deviceNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone.gen3")
                .foregroundStyle(.secondary)
            Text("All models run on-device via MLX · iPhone 15 Pro or newer required")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var tierPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                TierChip(label: "All", tint: .primary, isSelected: tierFilter == nil) {
                    tierFilter = nil
                }
                ForEach(CatalogModel.Tier.allCases, id: \.self) { tier in
                    TierChip(label: tier.rawValue, tint: tier.tintColor, isSelected: tierFilter == tier) {
                        tierFilter = tierFilter == tier ? nil : tier
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Model Card

private struct ModelCard: View {
    let model: CatalogModel
    let isActive: Bool
    let downloadProgress: ModelDownloadManager.DownloadProgress?
    let downloadError: String?
    let onDownload:  () -> Void
    let onCancel:    () -> Void
    let onSelect:    () -> Void
    let onDelete:    () -> Void

    private var isDownloading: Bool { downloadProgress != nil }
    private var isInstalled: Bool { model.isInstalled }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.headline)
                        if model.isRecommended {
                            Label("Recommended", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                                .labelStyle(.titleOnly)
                        }
                    }
                    Text("\(model.parameters) · \(model.sizeString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                tierBadge
            }

            Text(model.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Download progress
            if isDownloading, let progress = downloadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress.fraction)
                        .tint(model.tier.tintColor)
                    HStack {
                        Text(progress.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !progress.currentFileName.isEmpty {
                            Text(progress.currentFileName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            // Error
            if let error = downloadError, !isDownloading {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Action row
            HStack {
                Spacer()
                actionButtons
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var tierBadge: some View {
        Label(model.tier.rawValue, systemImage: model.tier.systemImage)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(model.tier.tintColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(model.tier.tintColor.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isDownloading {
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if isInstalled {
            HStack(spacing: 8) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(model.tier.tintColor)
                } else {
                    Button("Use", action: onSelect)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(model.tier.tintColor)
                }
            }
        } else {
            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(model.tier.tintColor)
        }
    }
}

// MARK: - Tier Chip

private struct TierChip: View {
    let label: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? tint : tint.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ModelBrowserView()
    }
}
