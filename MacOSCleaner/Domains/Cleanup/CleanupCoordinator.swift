import Foundation
import Observation
import OSLog
import AppKit

private extension Logger {
    static let coordinator = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "CleanupCoordinator")
}

@Observable
public final class CleanupCoordinator: @unchecked Sendable {
    private let stateMachine = CleanupStateMachine()
    private let engine: CleanupEngine
    private let journal: TransactionJournal
    private let settings: AppSettings
    private let trashManager: TrashManager
    private let itemManager: CleanupItemManager
    private let notifier: CleanupNotifier
    private var currentTask: Task<Void, Never>?
    
    public var state: CleanupState { stateMachine.state }
    public var currentStep: Int = 0
    public var totalSteps: Int = 1
    public var stepTitle: String = ""
    public var totalFreedMB: Int = 0
    public var totalFreedBytes: Int64 = 0
    public var cleanedItems: [CleanupResultItem] = []
    public var skippedItems: [SkippedCleanupItem] = []
    public var lastError: String? = nil
    public var scriptLogs: [String] = []
    
    private var pendingLogs: [String] = []
    private var isLogFlushScheduled = false
    
    public init(
        engine: CleanupEngine,
        journal: TransactionJournal,
        settings: AppSettings,
        trashManager: TrashManager = TrashManager(),
        itemManager: CleanupItemManager,
        notifier: CleanupNotifier = CleanupNotifier()
    ) {
        self.engine = engine
        self.journal = journal
        self.settings = settings
        self.trashManager = trashManager
        self.itemManager = itemManager
        self.notifier = notifier
    }
    
    @MainActor
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        do {
            try stateMachine.transition(to: .cancelled)
        } catch {
            Logger.coordinator.error("Failed to transition to cancelled: \(error.localizedDescription)")
        }
        Logger.coordinator.info("Cleanup cancelled by user")
    }
    
    @MainActor
    public func startScan(options: CleanupOptions) {
        currentTask?.cancel()
        currentTask = Task {
            do {
                if self.settings.emptyTrashDuringCleanup {
                    try await self.trashManager.requestTrashAccess()
                }
                
                try self.stateMachine.transition(to: .scanning)
                self.itemManager.clear()
                FileManager.clearSizeCache()
                self.lastError = nil
                self.scriptLogs = []
                self.pendingLogs = []
                self.isLogFlushScheduled = false
                self.skippedItems = []
                
                // Close running apps before scan for better cache cleanup
                await self.closeRunningApps()
                
                let categories = options.scanCategories()
                
                _ = try await self.engine.scan(categories: categories, options: options) { [weak self] event in
                    guard let self else { return }
                    Task { @MainActor in
                        self.handleEngineEvent(event)
                    }
                }
                
                // Allow final main-actor logs to process, then flush
                try? await Task.sleep(for: .milliseconds(100))
                self.flushLogs()

                // Review-only groups stay opt-in (never auto-selected).
                self.deselectReviewOnlyGroups()

                if self.settings.emptyTrashDuringCleanup {
                    await self.presentTrashItemsForReview()
                }
                
                try self.stateMachine.transition(to: .preview)
                
                self.notifier.sendScanComplete(
                    selectedSizeBytes: self.itemManager.selectedSizeBytes,
                    showNotifications: self.settings.showNotifications
                )
            } catch let error {
                self.flushLogs()
                Logger.coordinator.error("startScan failed: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
                do {
                    try self.stateMachine.transition(to: .failed)
                } catch {
                    Logger.coordinator.error("Failed to transition to failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    public func executeCleanup(options: CleanupOptions) {
        currentTask?.cancel()
        currentTask = Task {
            do {
                // Close running apps before cleanup
                await self.closeRunningApps()

                try self.stateMachine.transition(to: .executing)
                self.totalFreedMB = 0
                self.totalFreedBytes = 0
                self.cleanedItems = []
                self.lastError = nil
                self.scriptLogs = []
                self.pendingLogs = []
                self.isLogFlushScheduled = false
                
                let trashLabel = "trash_user_label".localized
                let selectedTrashURLs = self.itemManager.selectedLeafURLs(underParentLabel: trashLabel)
                if !selectedTrashURLs.isEmpty {
                    try await self.trashManager.requestTrashAccess()
                }

                let categories = self.itemManager.selectedCleanupCategories(from: options.categories())
                // Review-only categories — never run category-level wipe.
                let safeCategories = categories.filter {
                    $0 != .oldBackups && $0 != .aiModels && $0 != .installerPackages && $0 != .largeFiles
                }
                var records: [OperationRecord] = []
                var hadPartialFailure = false

                let results = try await self.engine.run(categories: safeCategories, dryRun: false, options: options) { [weak self] event in
                    guard let self else { return }
                    Task { @MainActor in
                        self.handleEngineEvent(event)
                    }
                }

                // Allow final main-actor logs to process, then flush
                try? await Task.sleep(for: .milliseconds(100))
                self.flushLogs()

                for result in results {
                    self.totalFreedMB += result.freedMB
                    self.totalFreedBytes += result.freedBytes
                    if result.freedBytes > 0 {
                        self.cleanedItems.append(CleanupResultItem(label: result.label, freedMB: result.freedMB, freedBytes: result.freedBytes))
                    }
                    if result.isPartialFailure {
                        hadPartialFailure = true
                        records.append(OperationRecord(id: UUID(), itemPath: result.label, status: "partial", bytesFreed: result.freedBytes))
                        self.skippedItems.append(SkippedCleanupItem(
                            label: result.label,
                            reason: "partial failure: removed=\(result.removedCount) skipped=\(result.skippedCount) failed=\(result.failedCount)"
                        ))
                    } else {
                        records.append(OperationRecord(id: UUID(), itemPath: result.label, status: "success", bytesFreed: result.freedBytes))
                    }
                }

                // Check for skipped categories from logs
                for log in self.scriptLogs {
                    if log.contains("⚠️"), log.contains("skipped") {
                        if let item = self.parseSkippedFromLog(log) {
                            self.skippedItems.append(item)
                        }
                    }
                }

                // Permanently delete only explicitly selected Trash items (never whole ~/.Trash).
                if !selectedTrashURLs.isEmpty {
                    self.totalSteps = self.currentStep + 1
                    self.currentStep += 1
                    self.stepTitle = "cleanup_emptying_trash".localized
                    let deletedBytes = try await self.trashManager.permanentlyDelete(urls: selectedTrashURLs)
                    let deletedMB = Int(deletedBytes / (1024 * 1024))
                    self.totalFreedMB += deletedMB
                    self.totalFreedBytes += deletedBytes
                    if deletedBytes > 0 {
                        self.cleanedItems.append(CleanupResultItem(label: trashLabel, freedMB: deletedMB, freedBytes: deletedBytes))
                    }
                    records.append(OperationRecord(id: UUID(), itemPath: trashLabel, status: "success", bytesFreed: deletedBytes))
                }

                // Move selected review-only items to Trash (never category-level wipe).
                let reviewGroups: [(CleanupCategory, String)] = [
                    (.oldBackups, "Old Backups"),
                    (.aiModels, "AI Models"),
                    (.installerPackages, "Installer Packages"),
                    (.largeFiles, "Large files"),
                ]
                for (category, logLabel) in reviewGroups {
                    let selectedURLs = self.selectedReviewLeafURLs(for: category)
                    guard !selectedURLs.isEmpty else { continue }
                    self.currentStep += 1
                    self.stepTitle = category.localizedTitle
                    var freed: Int64 = 0
                    for url in selectedURLs {
                        do {
                            try Task.checkCancellation()
                            let size = FileManager.default.getDirectorySize(url: url)
                            _ = try await self.trashManager.trashItem(at: url, policy: .cleanup)
                            freed += size
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            hadPartialFailure = true
                            Logger.coordinator.error("\(logLabel, privacy: .public) trash failed: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    let mb = Int(freed / (1024 * 1024))
                    self.totalFreedMB += mb
                    self.totalFreedBytes += freed
                    if freed > 0 {
                        self.cleanedItems.append(CleanupResultItem(label: category.localizedTitle, freedMB: mb, freedBytes: freed))
                    }
                    records.append(OperationRecord(
                        id: UUID(),
                        itemPath: category.localizedTitle,
                        status: hadPartialFailure ? "partial" : "success",
                        bytesFreed: freed
                    ))
                }

                let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: records)
                try await self.journal.log(transaction: transaction)

                if !self.skippedItems.isEmpty || hadPartialFailure {
                    let skippedList = self.skippedItems.map { "\($0.label) (\($0.reason))" }.joined(separator: ", ")
                    self.scriptLogs.append("⚠️ Cleanup completed with partial results. Skipped: \(skippedList)")
                    if hadPartialFailure {
                        self.lastError = "Cleanup finished with partial failures"
                        Logger.coordinator.warning("Cleanup completed with partial failures")
                    }
                }

                self.notifier.sendCleanupComplete(
                    totalFreedBytes: self.totalFreedBytes,
                    showNotifications: self.settings.showNotifications
                )

                try self.stateMachine.transition(to: .completed)
            } catch let error {
                self.flushLogs()
                Logger.coordinator.error("executeCleanup failed: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
                do {
                    try self.stateMachine.transition(to: .failed)
                } catch {
                    Logger.coordinator.error("Failed to transition to failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func parseSkippedFromLog(_ log: String) -> SkippedCleanupItem? {
        let patterns: [(category: CleanupCategory?, keywords: [String])] = [
            (.appContainers, ["App containers"]),
            (.orphanedRemnants, ["Orphaned remnants"]),
            (.orphanedFiles, ["Orphaned files"]),
            (.largeFiles, ["Large files"]),
            (.dynamicCacheDiscovery, ["Dynamic cache discovery"]),
            (.appCaches, ["App caches"]),
            (.packageManagers, ["Package managers"]),
            (.gradleMaven, ["Gradle"]),
            (.flutterDart, ["Flutter"]),
            (.xcode, ["Xcode"]),
            (.iosSimulators, ["iOS Simulators"]),
            (.androidCaches, ["Android caches"]),
            (.androidSDK, ["Android SDK"]),
            (.ideCaches, ["IDE"]),
            (.browserCaches, ["Browser caches"]),
            (.messagingMedia, ["Messaging"]),
            (.docker, ["Docker"]),
            (.languageCaches, ["Language caches"]),
            (.userLogs, ["User logs"]),
            (.systemCaches, ["System caches"]),
            (.dotfileCaches, ["Dotfile caches"]),
            (.scatteredJunk, ["Scattered junk"]),
            (.timeMachineSnapshots, ["Time Machine"]),
            (.iosBackups, ["iOS Backups"]),
            (.mailDownloads, ["Mail Downloads"]),
            (.savedAppState, ["Saved Application State"]),
            (.crashReporter, ["Crash Reporter"]),
            (.assetsV2, ["AssetsV2"]),
            (.cloudKitCache, ["CloudKit"]),
            (.swiftPMCache, ["SwiftPM"]),
            (.carthageCache, ["Carthage"]),
            (.steamCache, ["Steam"]),
            (.teamsCache, ["Teams"]),
            (.adobeCaches, ["Adobe"]),
            (.chromeExtraCaches, ["Chrome"]),
        ]

        guard let matched = patterns.first(where: { $0.keywords.contains(where: { log.contains($0) }) }) else {
            return nil
        }

        let label: String
        if let category = matched.category {
            label = category.localizedTitle
        } else {
            label = matched.keywords[0]
        }

        let reason: String
        if let range = log.range(of: "— ") {
            let afterDash = log[range.upperBound...]
            if let skippedRange = afterDash.range(of: ", skipped") {
                reason = String(afterDash[..<skippedRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            } else {
                reason = String(afterDash).trimmingCharacters(in: .whitespaces)
            }
        } else {
            reason = "unknown"
        }

        return SkippedCleanupItem(label: label, reason: reason)
    }
    
    @MainActor
    public func reset() {
        currentTask?.cancel()
        currentTask = nil
        stateMachine.reset()
        itemManager.clear()
        cleanedItems = []
        skippedItems = []
        totalFreedMB = 0
        currentStep = 0
        stepTitle = ""
        lastError = nil
        scriptLogs = []
    }

    @MainActor
    private func deselectReviewOnlyGroups() {
        for category in [CleanupCategory.oldBackups, .aiModels, .installerPackages, .largeFiles] {
            for label in category.previewLabels {
                itemManager.setSelection(underParentLabel: label, isSelected: false)
            }
        }
    }

    @MainActor
    private func selectedReviewLeafURLs(for category: CleanupCategory) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        for label in category.previewLabels {
            for url in itemManager.selectedLeafURLs(underParentLabel: label) {
                if seen.insert(NormalizedPath.key(url)).inserted {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    @MainActor
    private func presentTrashItemsForReview() async {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let trashLabel = "trash_user_label".localized
        guard FileManager.default.fileExists(atPath: trashURL.path),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
                options: []
              ) else {
            return
        }

        for url in contents {
            let size = FileManager.default.getDirectorySize(url: url)
            guard size > 0 else { continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            itemManager.appendFileItem(
                path: url.path,
                sizeBytes: size,
                modificationDate: modified,
                isDirectory: isDir.boolValue,
                category: trashLabel,
                parentName: trashLabel,
                isSelected: false
            )
        }

        if let idx = itemManager.items.firstIndex(where: { $0.label == trashLabel }) {
            itemManager.items[idx].isSelected = false
        }
    }

    @MainActor
    private func closeRunningApps() async {
        let appsToClose = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier &&
            !(app.bundleIdentifier ?? "").hasPrefix("com.apple.")
        }

        for app in appsToClose {
            app.terminate()
        }

        do {
            try await Task.sleep(for: .seconds(3))
        } catch {
            Logger.coordinator.warning("Sleep interrupted during app termination")
        }

        let safetyPolicy = ProcessSafetyPolicy()
        for app in appsToClose {
            if !app.isTerminated {
                let process = RunningProcess(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? "Unknown",
                    path: app.bundleURL?.path,
                    user: nil,
                    cpuPercent: 0,
                    memoryBytes: 0,
                    threadCount: 0,
                    startTime: nil,
                    parentPID: 0,
                    bundleID: app.bundleIdentifier
                )
                let permission = safetyPolicy.isKillable(process)
                if case .allowed = permission {
                    app.forceTerminate()
                    Logger.coordinator.info("Force terminated: \(app.localizedName ?? "Unknown")")
                } else if case .blocked(let reason) = permission {
                    Logger.coordinator.warning("Skipped force terminate for protected process: \(app.localizedName ?? "Unknown") - \(reason)")
                }
            }
        }
    }
    
    @MainActor
    private func handleEngineEvent(_ event: CleanupEngineEvent) {
        switch event {
        case .step(let current, let total, let title):
            self.currentStep = current
            self.totalSteps = total
            self.stepTitle = title
        case .preview(let label, let sizeMB, let deletable, let parentName, let description):
            Logger.coordinator.debug("Preview event: label=\(label, privacy: .public), size=\(sizeMB), parent=\(parentName ?? "none", privacy: .public), description=\(description ?? "none", privacy: .public)")
            self.itemManager.appendPreviewItem(label, size: sizeMB, deletable: deletable, parentName: parentName, description: description)
        case .result(let label, let freedMB):
            Logger.coordinator.debug("Result event: label=\(label, privacy: .public), freed=\(freedMB)")
            if freedMB > 0 {
                self.itemManager.appendPreviewItem(label, size: freedMB, deletable: true, parentName: nil, description: nil)
            }
        case .categoryResult(let category, let label, let freedMB):
            Logger.coordinator.debug("CategoryResult event: cat=\(category), label=\(label, privacy: .public), freed=\(freedMB)")
            if freedMB > 0, !hasPathBackedPreviewItems(for: category, label: label) {
                self.itemManager.appendPreviewItem(label, size: freedMB, deletable: true, parentName: category, description: nil)
            }
        case .log(let message):
            self.pendingLogs.append(message)
            self.scheduleLogFlushIfNeeded()
        case .fileItem(let path, let sizeBytes, let modificationDate, let isDirectory, let category, let parentName):
            let localizedCategory = CleanupCategory.localizedGroupTitle(for: category)
            let effectiveParent = parentName.map { CleanupCategory.localizedGroupTitle(for: $0) } ?? localizedCategory
            self.itemManager.appendFileItem(path: path, sizeBytes: sizeBytes, modificationDate: modificationDate, isDirectory: isDirectory, category: localizedCategory, parentName: effectiveParent)
        }
    }
    
    @MainActor
    private func scheduleLogFlushIfNeeded() {
        guard !isLogFlushScheduled else { return }
        isLogFlushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.flushLogs()
        }
    }
    
    @MainActor
    private func hasPathBackedPreviewItems(for category: String, label: String) -> Bool {
        itemManager.items.contains { item in
            let matchesCategory = item.label == category
                || CleanupCategory.localizedGroupTitle(for: item.label) == category
                || item.label == label
            guard matchesCategory else { return false }
            return item.children.contains { $0.path != nil }
        }
    }

    @MainActor
    private func flushLogs() {
        if !pendingLogs.isEmpty {
            self.scriptLogs.append(contentsOf: self.pendingLogs)
            self.pendingLogs.removeAll()
        }
        isLogFlushScheduled = false
    }
}
