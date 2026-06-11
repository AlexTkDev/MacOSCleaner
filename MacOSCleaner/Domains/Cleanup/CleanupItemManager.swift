import Foundation
import OSLog

private extension Logger {
    static let itemManager = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "CleanupItemManager")
}

@Observable
public final class CleanupItemManager {
    public var items: [CleanupPreviewItem] = []
    public var selectedItemId: UUID? = nil
    
    public init() {}
    
    public var selectedItem: CleanupPreviewItem? {
        guard let id = selectedItemId else { return nil }
        for item in items {
            if item.id == id { return item }
            if let child = item.children.first(where: { $0.id == id }) {
                return child
            }
        }
        return nil
    }
    
    public var selectedSizeMB: Int {
        var total = 0
        var seenLabels = Set<String>()
        var logs: [String] = []
        
        for item in items {
            if item.children.isEmpty {
                if item.isSelected && !seenLabels.contains(item.label) {
                    total += item.sizeMB
                    seenLabels.insert(item.label)
                    logs.append("Counted root: \(item.label) (\(item.sizeMB)MB)")
                }
            } else {
                seenLabels.insert(item.label)
                for child in item.children {
                    if child.isSelected && !seenLabels.contains(child.label) {
                        total += child.sizeMB
                        seenLabels.insert(child.label)
                        logs.append("Counted child of \(item.label): \(child.label) (\(child.sizeMB)MB)")
                    }
                }
            }
        }
        if total > 0 {
            Logger.itemManager.debug("Total selected calculation (\(total)MB):")
            logs.forEach { Logger.itemManager.debug("  - \($0, privacy: .public)") }
        }
        return total
    }
    
    public func toggleSelection(for itemId: UUID) {
        if let idx = items.firstIndex(where: { $0.id == itemId }) {
            let newValue = !items[idx].isSelected
            updateItemSelection(&items[idx], isSelected: newValue)
        } else {
            for i in items.indices {
                if let childIdx = items[i].children.firstIndex(where: { $0.id == itemId }) {
                    items[i].children[childIdx].isSelected.toggle()
                    items[i].isSelected = items[i].children.contains { $0.isSelected }
                    return
                }
            }
        }
    }
    
    public func selectItem(_ itemId: UUID?) {
        self.selectedItemId = itemId
    }
    
    public func updateAllSelection(isSelected: Bool) {
        for i in items.indices {
            updateItemSelection(&items[i], isSelected: isSelected)
        }
    }
    
    public func appendPreviewItem(_ label: String, size: Int, deletable: Bool, parentName: String?, description: String?) {
        let risk = deletable ? Self.determineRisk(for: label) : .protected
        let newItem = CleanupPreviewItem(
            label: label,
            sizeMB: size,
            risk: risk,
            isSelected: deletable,
            isDeletable: deletable,
            description: description
        )
        
        if let parentName = parentName, !parentName.isEmpty {
            if let idx = items.firstIndex(where: { $0.label == parentName }) {
                if !items[idx].children.contains(where: { $0.label == label }) {
                    items[idx].children.append(newItem)
                    items[idx].sizeMB = items[idx].children.reduce(0) { $0 + $1.sizeMB }
                }
            } else {
                let parent = CleanupPreviewItem(
                    label: parentName,
                    sizeMB: size,
                    risk: .safe,
                    isSelected: true,
                    isDeletable: true,
                    children: [newItem]
                )
                items.append(parent)
            }
        } else {
            if let idx = items.firstIndex(where: { $0.label == label }) {
                if items[idx].children.isEmpty {
                    items[idx].sizeMB = max(items[idx].sizeMB, size)
                }
            } else {
                items.append(newItem)
            }
        }
    }
    
    public func clear() {
        items = []
        selectedItemId = nil
    }
    
    private func updateItemSelection(_ item: inout CleanupPreviewItem, isSelected: Bool) {
        guard item.isDeletable else { return }
        item.isSelected = isSelected
        for i in item.children.indices {
            updateItemSelection(&item.children[i], isSelected: isSelected)
        }
    }
    
    static func determineRisk(for label: String) -> OperationRisk {
        let l = label.lowercased()
        if l.contains("xcode") || l.contains("android") || l.contains("gradle") {
            return .moderate
        }
        if l.contains("browser") || l.contains("cache") {
            return .safe
        }
        return .safe
    }
}
