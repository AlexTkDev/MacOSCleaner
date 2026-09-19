// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI
import AppKit
import QuickLook
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ImageIO

public struct DuplicatesView: View {
    @State private var viewModel = DuplicatesViewModel()
    @State private var selectedGroupId: UUID?
    @State private var quickLookURL: URL?

    public init() {}

    private var selectedGroup: DuplicateGroup? {
        if let selectedGroupId, let group = viewModel.filteredGroups.first(where: { $0.id == selectedGroupId }) {
            return group
        }
        return viewModel.filteredGroups.first
    }

    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                headerControlsView

                if viewModel.isScanning {
                    scanningProgressView
                } else if viewModel.groups.isEmpty {
                    emptyStateView
                } else {
                    HSplitView {
                        duplicateGroupsMasterView
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                        duplicateGroupDetailContainer
                            .frame(minWidth: 460, maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !viewModel.groups.isEmpty && !viewModel.isScanning {
                    bottomActionBar
                }
            }
            .padding()
        }
        .quickLookPreview($quickLookURL)
        .alert("duplicate_trash_confirm_title".localized, isPresented: $viewModel.showConfirmationAlert) {
            Button("duplicate_trash_confirm_action".localized, role: .destructive) {
                viewModel.trashSelected()
            }
            Button("cancel".localized, role: .cancel) {}
        } message: {
            Text(String(format: "duplicate_trash_confirm_message".localized, viewModel.totalSelectedCount, FileCleanupActor.formatBytes(viewModel.totalSelectedBytes)))
        }
    }

    private var headerControlsView: some View {
        HStack(spacing: 12) {
            // Preset / Select Folder Menu
            Menu {
                Button(action: { selectPresetFolder(FileManager.default.homeDirectoryForCurrentUser) }) {
                    Label("duplicate_folder_home".localized, systemImage: "house")
                }
                Button(action: { selectPresetFolder(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!) }) {
                    Label("duplicate_folder_downloads".localized, systemImage: "arrow.down.circle")
                }
                Button(action: { selectPresetFolder(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!) }) {
                    Label("duplicate_folder_documents".localized, systemImage: "doc")
                }
                Divider()
                Button(action: openFolderPicker) {
                    Label("duplicate_folder_custom".localized, systemImage: "folder.badge.plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(viewModel.selectedFolderURL.lastPathComponent)
                        .lineLimit(1)
                }
            }
            .secondaryGlassButtonStyle()

            // Search filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("duplicate_search_placeholder".localized, text: $viewModel.searchFilter)
                    .textFieldStyle(.plain)
                if !viewModel.searchFilter.isEmpty {
                    Button(action: { viewModel.searchFilter = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Smart Selection Menu
            if !viewModel.groups.isEmpty && !viewModel.isScanning {
                Menu {
                    ForEach(SmartSelectStrategy.allCases) { strategy in
                        Button(action: { viewModel.applyStrategy(strategy) }) {
                            HStack {
                                Text(strategy.localizedTitle)
                                if viewModel.currentStrategy == strategy {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("duplicate_smart_select".localized, systemImage: "wand.and.stars")
                }
                .secondaryGlassButtonStyle()
            }

            // Scan / Cancel Button
            if viewModel.isScanning {
                Button("cancel".localized) {
                    viewModel.cancelScan()
                }
                .secondaryGlassButtonStyle()
            } else {
                Button("duplicate_start_scan".localized) {
                    viewModel.startScan()
                }
                .prominentGlassButtonStyle(tint: .accentColor)
            }
        }
    }

    private var scanningProgressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(viewModel.statusMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("duplicate_empty_title".localized)
                .font(.system(size: 16, weight: .semibold))
            Text(viewModel.statusMessage.isEmpty ? "duplicate_empty_subtitle".localized : viewModel.statusMessage)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("duplicate_start_scan".localized) {
                viewModel.startScan()
            }
            .prominentGlassButtonStyle(tint: .accentColor)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Master View (Left Panel)

    private var duplicateGroupsMasterView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.filteredGroups) { group in
                    duplicateGroupRow(group: group, isSelected: (selectedGroup?.id == group.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedGroupId = group.id
                            }
                        }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func duplicateGroupRow(group: DuplicateGroup, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(String(format: "duplicate_copies_count".localized, group.items.count))
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Color.white.opacity(0.75) : .secondary)
            }

            Spacer()

            Text(FileCleanupActor.formatBytes(group.potentialWastedBytes))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.90),
                                Color.accentColor.opacity(0.75)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.50), location: 0.0),
                                        .init(color: Color.accentColor.opacity(0.5), location: 0.5),
                                        .init(color: Color.white.opacity(0.12), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Detail View (Right Panel)

    @ViewBuilder
    private var duplicateGroupDetailContainer: some View {
        if let group = selectedGroup {
            VStack(spacing: 12) {
                previewCard(group: group)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(group.items) { item in
                            duplicateFileRow(group: group, item: item)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.leading, 8)
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("duplicate_no_selection".localized)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewCard(group: DuplicateGroup) -> some View {
        let primaryItem = group.items.first
        let fileURL = primaryItem?.url ?? URL(fileURLWithPath: "/")
        let isImage = isImageFile(url: fileURL)

        return VStack(spacing: 10) {
            if isImage {
                DuplicateThumbnailView(url: fileURL, targetSize: CGSize(width: 512, height: 320))
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        quickLookURL = fileURL
                    }
                    .help("disk_analyzer_quick_look".localized)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .padding(.top, 4)
            }

            VStack(spacing: 3) {
                Text(primaryItem?.name ?? group.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metadataString(for: fileURL, fileSize: group.fileSize))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isImage ? 14 : 12)
        .padding(.horizontal, 12)
        .glassCard(cornerRadius: 12)
    }

    private func duplicateFileRow(group: DuplicateGroup, item: DuplicateFileItem) -> some View {
        let original = group.isOriginal(item)
        let isImage = isImageFile(url: item.url)

        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { _ in viewModel.toggleItemSelection(groupId: group.id, itemId: item.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Button(action: {
                if isImage {
                    quickLookURL = item.url
                }
            }) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(isImage ? "disk_analyzer_quick_look".localized : "")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    fileBadge(isOriginal: original)
                }

                Text(FileCleanupActor.shortPath(item.path))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isImage {
                    quickLookURL = item.url
                }
            }

            Spacer()

            if let date = item.modificationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("duplicate_reveal_in_finder".localized)
        }
        .padding(10)
        .background(item.isSelected ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(item.isSelected ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func isImageFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let imageExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp", "heic", "heif",
            "webp", "raw", "cr2", "nef", "arw", "dng", "svg", "ico"
        ]
        if imageExtensions.contains(ext) {
            return true
        }
        if let uti = UTType(filenameExtension: ext) {
            return uti.conforms(to: .image)
        }
        return false
    }

    @ViewBuilder
    private func fileBadge(isOriginal: Bool) -> some View {
        Text(isOriginal ? "duplicate_badge_original".localized : "duplicate_badge_duplicate".localized)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isOriginal ? .green : .orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill((isOriginal ? Color.green : Color.orange).opacity(0.14))
            )
            .overlay(
                Capsule()
                    .strokeBorder((isOriginal ? Color.green : Color.orange).opacity(0.28), lineWidth: 1)
            )
    }

    private func metadataString(for url: URL, fileSize: Int64) -> String {
        var parts: [String] = []

        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue {
            parts.append("\(width) × \(height)")
        }

        let ext = url.pathExtension.uppercased()
        if !ext.isEmpty {
            parts.append(ext)
        }

        parts.append(FileCleanupActor.formatBytes(fileSize))

        return parts.joined(separator: " • ")
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "duplicate_selected_summary".localized, viewModel.totalSelectedCount))
                    .font(.system(size: 13, weight: .medium))
                Text(String(format: "duplicate_selected_reclaim".localized, FileCleanupActor.formatBytes(viewModel.totalSelectedBytes)))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                viewModel.showConfirmationAlert = true
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("duplicate_move_to_trash".localized)
                }
            }
            .prominentGlassButtonStyle(tint: .red)
            .disabled(viewModel.totalSelectedCount == 0 || viewModel.isTrashing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
    }

    private func selectPresetFolder(_ url: URL) {
        viewModel.selectedFolderURL = url
        viewModel.startScan()
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "select".localized

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.selectedFolderURL = url
            viewModel.startScan()
        }
    }
}

// MARK: - Thumbnail Helper

private struct DuplicateThumbnailView: View {
    let url: URL
    var targetSize: CGSize = CGSize(width: 128, height: 128)
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: url) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(fileAt: url, size: targetSize, scale: scale, representationTypes: .all)
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            self.thumbnail = rep.nsImage
        } catch {
            // Fallback icon already used in view
        }
    }
}

#Preview {
    DuplicatesView()
}
