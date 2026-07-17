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
                
                if self.settings.emptyTrashDuringCleanup {
                    let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
                    let trashSizeBytes = FileManager.default.getDirectorySize(url: trashURL)
                    let trashSizeMB = Int(max(0, trashSizeBytes / (1024 * 1024)))
                    
                    let localizedLabel = "trash_user_label".localized
                    let description = "trash_user_description".localized
                    
                    let trashItem = CleanupPreviewItem(
                        label: localizedLabel,
                        sizeMB: trashSizeMB,
                        sizeBytes: trashSizeBytes,
                        risk: .safe,
                        isSelected: true,
                        isDeletable: true,
                        description: description
                    )
                    self.itemManager.items.append(trashItem)
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
                
                let isTrashSelected = self.itemManager.items.contains { item in
                    item.isSelected && item.label == "trash_user_label".localized
                }
                
                if isTrashSelected {
                    try await self.trashManager.requestTrashAccess()
                }
                
                let categories = self.itemManager.selectedCleanupCategories(from: options.categories())
                var records: [OperationRecord] = []
                
                let results = try await self.engine.run(categories: categories, dryRun: false, options: options) { [weak self] event in
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
                    self.cleanedItems.append(CleanupResultItem(label: result.label, freedMB: result.freedMB, freedBytes: result.freedBytes))
                    records.append(OperationRecord(id: UUID(), itemPath: result.label, status: "success", bytesFreed: result.freedBytes))
                }
                
                // Check for skipped categories from logs
                for log in self.scriptLogs {
                    if log.contains("⚠️"), log.contains("skipped") {
                        if let item = self.parseSkippedFromLog(log) {
                            self.skippedItems.append(item)
                        }
                    }
                }
                
                if isTrashSelected {
                    self.totalSteps = self.currentStep + 1
                    self.currentStep += 1
                    self.stepTitle = "cleanup_emptying_trash".localized
                    let deletedBytes = try await self.trashManager.emptyTrash()
                    let deletedMB = Int(deletedBytes / (1024 * 1024))
                    
                    let trashLabel = "trash_user_label".localized
                    self.totalFreedMB += deletedMB
                    self.totalFreedBytes += deletedBytes
                    self.cleanedItems.append(CleanupResultItem(label: trashLabel, freedMB: deletedMB, freedBytes: deletedBytes))
                    records.append(OperationRecord(id: UUID(), itemPath: "~/.Trash", status: "success", bytesFreed: deletedBytes))
                }
                
                let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: records)
                try await self.journal.log(transaction: transaction)
                
                if !self.skippedItems.isEmpty {
                    let skippedList = self.skippedItems.map { "\($0.label) (\($0.reason))" }.joined(separator: ", ")
                    self.scriptLogs.append("⚠️ Cleanup completed with partial results. Skipped: \(skippedList)")
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
