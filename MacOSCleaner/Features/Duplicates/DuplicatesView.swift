// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI
import AppKit

public struct DuplicatesView: View {
    @State private var viewModel = DuplicatesViewModel()

    public init() {}

    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                headerControlsView

                if viewModel.isScanning {
                    scanningProgressView
                } else if viewModel.groups.isEmpty {
                    emptyStateView
                } else {
                    duplicateGroupsListView
                }

                if !viewModel.groups.isEmpty && !viewModel.isScanning {
                    bottomActionBar
                }
            }
            .padding()
        }
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
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

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
    
            }

            // Scan / Cancel Button
            if viewModel.isScanning {
                Button("cancel".localized) {
                    viewModel.cancelScan()
                }
                .buttonStyle(.bordered)
            } else {
                Button("duplicate_start_scan".localized) {
                    viewModel.startScan()
                }
                .buttonStyle(.borderedProminent)
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
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var duplicateGroupsListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.filteredGroups) { group in
                    duplicateGroupCard(group: group)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func duplicateGroupCard(group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.accentColor)
                Text(String(format: "duplicate_group_title".localized, group.items.count, FileCleanupActor.formatBytes(group.fileSize)))
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(String(format: "duplicate_group_wasted".localized, FileCleanupActor.formatBytes(group.selectedWastedBytes)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            Divider()

            VStack(spacing: 6) {
                ForEach(group.items) { item in
                    duplicateItemRow(group: group, item: item)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func duplicateItemRow(group: DuplicateGroup, item: DuplicateFileItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { _ in viewModel.toggleItemSelection(groupId: group.id, itemId: item.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(FileCleanupActor.shortPath(item.path))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("duplicate_reveal_in_finder".localized)
        }
        .padding(8)
        .background(item.isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }

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
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(viewModel.totalSelectedCount == 0 || viewModel.isTrashing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
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

#Preview {
    DuplicatesView()
}
