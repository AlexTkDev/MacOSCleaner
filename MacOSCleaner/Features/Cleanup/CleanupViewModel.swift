import Foundation
import Observation
import OSLog

@Observable
public final class CleanupViewModel {
    public let coordinator: CleanupCoordinator
    public let itemManager: CleanupItemManager
    public var options = ShellCleanupAdapter.CleanupOptions()
    
    public var state: CleanupState { coordinator.state }
    public var currentStep: Int { coordinator.currentStep }
    public var totalSteps: Int { coordinator.totalSteps }
    public var stepTitle: String { coordinator.stepTitle }
    public var items: [CleanupPreviewItem] { itemManager.items }
    public var totalFreedMB: Int { coordinator.totalFreedMB }
    public var cleanedItems: [CleanupResultItem] { coordinator.cleanedItems }
    public var lastError: String? { coordinator.lastError }
    public var scriptLogs: [String] { coordinator.scriptLogs }
    public var selectedItemId: UUID? {
        get { itemManager.selectedItemId }
        set { itemManager.selectedItemId = newValue }
    }
    public var selectedSizeMB: Int { itemManager.selectedSizeMB }
    public var selectedItem: CleanupPreviewItem? { itemManager.selectedItem }
    
    public init(adapter: ShellCleanupAdapter, journal: TransactionJournal, settings: AppSettings, trashManager: TrashManager = TrashManager()) {
        let itemManager = CleanupItemManager()
        self.itemManager = itemManager
        self.coordinator = CleanupCoordinator(
            adapter: adapter,
            journal: journal,
            settings: settings,
            trashManager: trashManager,
            itemManager: itemManager
        )
    }
    
    @MainActor
    public func cancel() {
        coordinator.cancel()
    }
    
    @MainActor
    public func startScan() {
        coordinator.startScan(options: options)
    }
    
    @MainActor
    public func executeCleanup() {
        coordinator.executeCleanup(options: options)
    }
    
    @MainActor
    public func reset() {
        coordinator.reset()
        options = ShellCleanupAdapter.CleanupOptions()
    }
    
    public func toggleSelection(for itemId: UUID) {
        itemManager.toggleSelection(for: itemId)
    }
    
    public func selectItem(_ itemId: UUID?) {
        itemManager.selectItem(itemId)
    }
    
    public func updateAllSelection(isSelected: Bool) {
        itemManager.updateAllSelection(isSelected: isSelected)
    }
}
