import Foundation
import Observation
import OSLog

private extension Logger {
    static let coordinator = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "CleanupCoordinator")
}

@Observable
public final class CleanupCoordinator {
    private let stateMachine = CleanupStateMachine()
    private let adapter: ShellCleanupAdapter
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
    public var cleanedItems: [CleanupResultItem] = []
    public var lastError: String? = nil
    public var scriptLogs: [String] = []
    
    public init(
        adapter: ShellCleanupAdapter,
        journal: TransactionJournal,
        settings: AppSettings,
        trashManager: TrashManager = TrashManager(),
        itemManager: CleanupItemManager,
        notifier: CleanupNotifier = CleanupNotifier()
    ) {
        self.adapter = adapter
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
        try? stateMachine.transition(to: .cancelled)
        Logger.coordinator.info("Cleanup cancelled by user")
    }
    
    @MainActor
    public func startScan(options: ShellCleanupAdapter.CleanupOptions) {
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
                
                let stream = self.adapter.runCleanup(scanOnly: true, options: options)
                for try await event in stream {
                    switch event {
                    case .step(let current, let total, let title):
                        self.currentStep = current
                        self.totalSteps = total
                        self.stepTitle = title
                    case .preview(let label, let size, let deletable, let parentName, let description):
                        Logger.coordinator.debug("Preview event: label=\(label, privacy: .public), size=\(size), parent=\(parentName ?? "none", privacy: .public), description=\(description ?? "none", privacy: .public)")
                        self.itemManager.appendPreviewItem(label, size: size, deletable: deletable, parentName: parentName, description: description)
                    case .log(let message):
                        self.scriptLogs.append(message)
                    case .result: break
                    }
                }
                
                if self.settings.emptyTrashDuringCleanup {
                    let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
                    let trashSizeBytes = FileManager.default.getDirectorySize(url: trashURL)
                    let trashSizeMB = Int(max(0, trashSizeBytes / (1024 * 1024)))
                    
                    let localizedLabel = "trash_user_label".localized
                    let description = "trash_user_description".localized
                    
                    let trashItem = CleanupPreviewItem(
                        label: localizedLabel,
                        sizeMB: trashSizeMB,
                        risk: .safe,
                        isSelected: true,
                        isDeletable: true,
                        description: description
                    )
                    self.itemManager.items.append(trashItem)
                }
                
                try self.stateMachine.transition(to: .preview)
                
                self.notifier.sendScanComplete(
                    selectedSizeMB: self.itemManager.selectedSizeMB,
                    showNotifications: self.settings.showNotifications
                )
            } catch let error {
                Logger.coordinator.error("startScan failed: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
                try? self.stateMachine.transition(to: .failed)
            }
        }
    }
    
    @MainActor
    public func executeCleanup(options: ShellCleanupAdapter.CleanupOptions) {
        currentTask?.cancel()
        currentTask = Task {
            do {
                try self.stateMachine.transition(to: .executing)
                self.totalFreedMB = 0
                self.cleanedItems = []
                self.lastError = nil
                self.scriptLogs = []
                
                let isTrashSelected = self.itemManager.items.contains { item in
                    item.isSelected && item.label == "trash_user_label".localized
                }
                
                if isTrashSelected {
                    try await self.trashManager.requestTrashAccess()
                }
                
                let selectedPaths = self.itemManager.items.filter { $0.isSelected && $0.label != "trash_user_label".localized }.map { $0.label }
                let stream = self.adapter.runCleanup(options: options, selectedPaths: selectedPaths)
                var records: [OperationRecord] = []
                
                for try await event in stream {
                    switch event {
                    case .step(let current, let total, let title):
                        self.currentStep = current
                        self.totalSteps = total + (isTrashSelected ? 1 : 0)
                        self.stepTitle = title
                    case .result(let label, let freed):
                        self.totalFreedMB += freed
                        self.cleanedItems.append(CleanupResultItem(label: label, freedMB: freed))
                        records.append(OperationRecord(id: UUID(), itemPath: label, status: "success", bytesFreed: Int64(freed * 1024 * 1024)))
                    case .log(let message):
                        self.scriptLogs.append(message)
                    case .preview: break
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
                    self.cleanedItems.append(CleanupResultItem(label: trashLabel, freedMB: deletedMB))
                    records.append(OperationRecord(id: UUID(), itemPath: "~/.Trash", status: "success", bytesFreed: deletedBytes))
                }
                
                let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: records)
                try await self.journal.log(transaction: transaction)
                
                self.notifier.sendCleanupComplete(
                    totalFreedMB: self.totalFreedMB,
                    showNotifications: self.settings.showNotifications
                )
                
                try self.stateMachine.transition(to: .completed)
            } catch let error {
                Logger.coordinator.error("executeCleanup failed: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
                try? self.stateMachine.transition(to: .failed)
            }
        }
    }
    
    @MainActor
    public func reset() {
        currentTask?.cancel()
        currentTask = nil
        stateMachine.reset()
        itemManager.clear()
        cleanedItems = []
        totalFreedMB = 0
        currentStep = 0
        stepTitle = ""
        lastError = nil
        scriptLogs = []
    }
}
