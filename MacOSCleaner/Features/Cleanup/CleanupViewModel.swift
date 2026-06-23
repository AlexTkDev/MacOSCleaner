import Foundation
import Observation
import OSLog
import AppKit

@Observable
public final class CleanupViewModel {
    public let coordinator: CleanupCoordinator
    public let itemManager: CleanupItemManager
    public var options = CleanupOptions()

    public var state: CleanupState { coordinator.state }
    public var currentStep: Int { coordinator.currentStep }
    public var totalSteps: Int { coordinator.totalSteps }
    public var stepTitle: String { coordinator.stepTitle }
    public var items: [CleanupPreviewItem] { itemManager.items }
    public var totalFreedMB: Int { coordinator.totalFreedMB }
    public var cleanedItems: [CleanupResultItem] { coordinator.cleanedItems }
    public var skippedItems: [SkippedCleanupItem] { coordinator.skippedItems }
    public var lastError: String? { coordinator.lastError }
    public var scriptLogs: [String] { coordinator.scriptLogs }
    public var selectedItemId: UUID? {
        get { itemManager.selectedItemId }
        set { itemManager.selectedItemId = newValue }
    }
    public var selectedSizeMB: Int { itemManager.selectedSizeMB }
    public var selectedItem: CleanupPreviewItem? { itemManager.selectedItem }
    public var expandedCategoryIds: Set<UUID> { itemManager.expandedCategoryIds }

    public init(engine: CleanupEngine, journal: TransactionJournal, settings: AppSettings, trashManager: TrashManager = TrashManager()) {
        let itemManager = CleanupItemManager()
        self.itemManager = itemManager
        self.coordinator = CleanupCoordinator(
            engine: engine,
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
    public func closeRunningApps() async {
        let appsToClose = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier &&
            !(app.bundleIdentifier ?? "").hasPrefix("com.apple.")
        }

        for app in appsToClose {
            app.terminate()
        }

        try? await Task.sleep(for: .seconds(3))

        for app in appsToClose {
            app.forceTerminate()
        }
    }

    @MainActor
    public func reset() {
        coordinator.reset()
        options = CleanupOptions()
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

    public func toggleCategoryExpansion(_ categoryId: UUID) {
        itemManager.toggleCategoryExpansion(categoryId)
    }

    public func showAllItems(_ categoryId: UUID) {
        itemManager.showAllItems(categoryId)
    }

    public func visibleItems(for categoryId: UUID) -> [CleanupPreviewItem] {
        itemManager.visibleItems(for: categoryId)
    }

    public func hasMoreItems(_ categoryId: UUID) -> Bool {
        itemManager.hasMoreItems(categoryId)
    }

    public func remainingCount(_ categoryId: UUID) -> Int {
        itemManager.remainingCount(categoryId)
    }

    public func isExpanded(_ categoryId: UUID) -> Bool {
        itemManager.expandedCategoryIds.contains(categoryId)
    }
}
