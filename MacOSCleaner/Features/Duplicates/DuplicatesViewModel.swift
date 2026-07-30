// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import Foundation
import SwiftUI
import OSLog

private extension Logger {
    static let duplicatesVM = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "DuplicatesViewModel")
}

@Observable
@MainActor
public final class DuplicatesViewModel {
    public var selectedFolderURL: URL
    public var isScanning: Bool = false
    public var isTrashing: Bool = false
    public var progressStage: DuplicateFinderEngine.ScanStage = .collectingFiles
    public var filesScanned: Int = 0
    public var groups: [DuplicateGroup] = []
    public var currentStrategy: SmartSelectStrategy = .keepOldest
    public var statusMessage: String = ""
    public var showConfirmationAlert: Bool = false
    public var searchFilter: String = ""

    private let engine: DuplicateFinderEngine
    private var scanTask: Task<Void, Never>?

    public var totalSelectedBytes: Int64 {
        groups.reduce(0) { $0 + $1.selectedWastedBytes }
    }

    public var totalSelectedCount: Int {
        groups.reduce(0) { $0 + $1.items.filter(\.isSelected).count }
    }

    public var totalPotentialWastedBytes: Int64 {
        groups.reduce(0) { $0 + $1.potentialWastedBytes }
    }

    public var filteredGroups: [DuplicateGroup] {
        guard !searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return groups
        }
        let query = searchFilter.lowercased()
        return groups.compactMap { group in
            let matchingItems = group.items.filter { $0.name.lowercased().contains(query) || $0.path.lowercased().contains(query) }
            guard !matchingItems.isEmpty else { return nil }
            var copy = group
            copy.items = matchingItems
            return copy
        }
    }

    public init(engine: DuplicateFinderEngine = DuplicateFinderEngine()) {
        self.engine = engine
        self.selectedFolderURL = FileManager.default.homeDirectoryForCurrentUser
    }

    public func startScan() {
        guard !isScanning else { return }
        isScanning = true
        groups = []
        filesScanned = 0
        statusMessage = "duplicate_scanning_start".localized

        scanTask = Task {
            do {
                let foundGroups = try await engine.scan(
                    directory: selectedFolderURL,
                    progress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.progressStage = progress.stage
                            self.filesScanned = progress.filesScanned
                            self.updateStatusMessage(stage: progress.stage)
                        }
                    }
                )

                guard !Task.isCancelled else { return }
                self.groups = foundGroups
                self.applyStrategy(self.currentStrategy)
                self.isScanning = false
                self.statusMessage = String(format: "duplicate_scan_completed".localized, foundGroups.count)
                Logger.duplicatesVM.info("Scan completed with \(foundGroups.count) duplicate groups")
            } catch is CancellationError {
                self.isScanning = false
                self.statusMessage = "duplicate_scan_cancelled".localized
                Logger.duplicatesVM.info("Scan cancelled")
            } catch {
                self.isScanning = false
                self.statusMessage = String(format: "duplicate_scan_failed".localized, error.localizedDescription)
                Logger.duplicatesVM.error("Scan failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        statusMessage = "duplicate_scan_cancelled".localized
    }

    public func applyStrategy(_ strategy: SmartSelectStrategy) {
        self.currentStrategy = strategy
        Task {
            let updated = await engine.applySmartSelect(groups: groups, strategy: strategy)
            self.groups = updated
        }
    }

    public func toggleItemSelection(groupId: UUID, itemId: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupId }) else { return }
        guard let iIdx = groups[gIdx].items.firstIndex(where: { $0.id == itemId }) else { return }
        groups[gIdx].items[iIdx].isSelected.toggle()
    }

    public func trashSelected() {
        guard totalSelectedCount > 0 else { return }
        isTrashing = true

        Task {
            do {
                let result = try await engine.trashSelectedFiles(groups: groups)
                guard !Task.isCancelled else { return }
                
                // Re-scan or filter out deleted files
                let trashedGroupIds = Set(groups.flatMap { g in g.items.filter(\.isSelected).map(\.id) })
                self.groups = self.groups.compactMap { group in
                    var g = group
                    g.items.removeAll { trashedGroupIds.contains($0.id) }
                    return g.items.count > 1 ? g : nil
                }

                self.isTrashing = false
                self.statusMessage = String(format: "duplicate_trash_completed".localized, result.removedCount, FileCleanupActor.formatBytes(result.freedBytes))
                Logger.duplicatesVM.info("Trashed \(result.removedCount) files freeing \(result.freedBytes) bytes")
            } catch {
                self.isTrashing = false
                self.statusMessage = String(format: "duplicate_trash_failed".localized, error.localizedDescription)
                Logger.duplicatesVM.error("Trash failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func updateStatusMessage(stage: DuplicateFinderEngine.ScanStage) {
        switch stage {
        case .collectingFiles:
            statusMessage = String(format: "duplicate_stage_collecting".localized, filesScanned)
        case .sizeFiltering:
            statusMessage = "duplicate_stage_size_filtering".localized
        case .headerHashing(let current, let total):
            statusMessage = String(format: "duplicate_stage_header_hashing".localized, current, total)
        case .fullHashing(let current, let total):
            statusMessage = String(format: "duplicate_stage_full_hashing".localized, current, total)
        case .completed:
            statusMessage = "duplicate_stage_completed".localized
        }
    }
}
