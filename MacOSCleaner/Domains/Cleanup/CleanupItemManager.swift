import Foundation
import OSLog

private extension Logger {
    static let itemManager = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "CleanupItemManager")
}

@Observable
public final class CleanupItemManager {
    public var items: [CleanupPreviewItem] = []
    public var selectedItemId: UUID? = nil
    public var expandedCategoryIds: Set<UUID> = []
    public var showingAllIds: Set<UUID> = []

    private let maxVisibleItems = 50

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
        Int(selectedSizeBytes / (1024 * 1024))
    }

    public var selectedSizeBytes: Int64 {
        var seenPaths = Set<String>()
        return items.reduce(0) { $0 + Self.selectedSizeBytes(for: $1, seenPaths: &seenPaths) }
    }

    // MARK: - File Item Append (new hierarchical flow)

    public func appendFileItem(path: String, sizeBytes: Int64, modificationDate: Date?, isDirectory: Bool, category: String, parentName: String?, isSelected: Bool = true) {
        let sizeMB = max(1, Int(sizeBytes / (1024 * 1024)))
        let risk = Self.determineRisk(for: path)

        let newItem = CleanupPreviewItem(
            label: Self.shortLabel(from: path),
            sizeMB: sizeMB,
            sizeBytes: sizeBytes,
            risk: risk,
            isSelected: isSelected,
            isDeletable: true,
            path: path,
            modificationDate: modificationDate,
            category: category
        )

        let targetParent = parentName ?? category

        if let idx = items.firstIndex(where: { $0.label == targetParent }) {
            if !items[idx].children.contains(where: { $0.path == path }) {
                items[idx].children.append(newItem)
                items[idx].sizeMB = items[idx].children.reduce(0) { $0 + $1.sizeMB }
                items[idx].sizeBytes = items[idx].children.reduce(0) { $0 + $1.sizeBytes }
                items[idx].isSelected = items[idx].children.contains(where: \.isSelected)
            }
        } else {
            let parent = CleanupPreviewItem(
                label: targetParent,
                sizeMB: sizeMB,
                sizeBytes: sizeBytes,
                risk: Self.determineRisk(for: targetParent),
                isSelected: isSelected,
                isDeletable: true,
                children: [newItem]
            )
            items.append(parent)
        }
    }

    /// Selected leaf paths under a parent preview group (Trash, Old Backups, …).
    public func selectedLeafURLs(underParentLabel label: String) -> [URL] {
        guard let parent = items.first(where: { $0.label == label }) else { return [] }
        return parent.children.compactMap { child in
            guard child.isSelected, let path = child.path else { return nil }
            return NormalizedPath.url(path)
        }
    }

    public func setSelection(underParentLabel label: String, isSelected: Bool) {
        guard let idx = items.firstIndex(where: { $0.label == label }) else { return }
        updateItemSelection(&items[idx], isSelected: isSelected)
    }

    // MARK: - Legacy Preview Item Append (backward compatibility)

    public func appendPreviewItem(_ label: String, size: Int, deletable: Bool, parentName: String?, description: String?) {
        let risk = deletable ? Self.determineRisk(for: label) : .protected
        let sizeBytes = Int64(size) * 1024 * 1024
        let newItem = CleanupPreviewItem(
            label: label,
            sizeMB: size,
            sizeBytes: sizeBytes,
            risk: risk,
            isSelected: deletable,
            isDeletable: deletable,
            description: description
        )

        if let parentName = parentName, !parentName.isEmpty {
            if let idx = items.firstIndex(where: { $0.label == parentName }) {
                if !items[idx].children.contains(where: { $0.label == label }) {
                    if !items[idx].children.isEmpty {
                        items[idx].sizeMB = max(items[idx].sizeMB, size)
                        items[idx].sizeBytes = max(items[idx].sizeBytes, sizeBytes)
                    } else {
                        items[idx].children.append(newItem)
                        items[idx].sizeMB = items[idx].children.reduce(0) { $0 + $1.sizeMB }
                        items[idx].sizeBytes = items[idx].children.reduce(0) { $0 + $1.sizeBytes }
                    }
                }
            } else {
                let parent = CleanupPreviewItem(
                    label: parentName,
                    sizeMB: size,
                    sizeBytes: sizeBytes,
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
                    items[idx].sizeBytes = max(items[idx].sizeBytes, sizeBytes)
                }
            } else {
                items.append(newItem)
            }
        }
    }

    // MARK: - Selection

    public func toggleSelection(for itemId: UUID) {
        if let idx = items.firstIndex(where: { $0.id == itemId }) {
            let newValue = !items[idx].isSelected
            updateItemSelection(&items[idx], isSelected: newValue)
        } else {
            for i in items.indices {
                if let childIdx = items[i].children.firstIndex(where: { $0.id == itemId }) {
                    items[i].children[childIdx].isSelected.toggle()
                    let allSelected = items[i].children.allSatisfy { $0.isSelected }
                    let noneSelected = items[i].children.allSatisfy { !$0.isSelected }
                    items[i].isSelected = allSelected || !noneSelected
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

    public func selectedCleanupCategories(from categories: [CleanupCategory]) -> [CleanupCategory] {
        let selectedLabels = Set(items.filter { Self.selectedSizeBytes(for: $0) > 0 }.map(\.label))

        return categories.filter { category in
            !category.previewLabels.isDisjoint(with: selectedLabels) || !hasPreviewItem(for: category)
        }
    }

    // MARK: - Expansion

    public func toggleCategoryExpansion(_ categoryId: UUID) {
        if expandedCategoryIds.contains(categoryId) {
            expandedCategoryIds.remove(categoryId)
        } else {
            expandedCategoryIds.insert(categoryId)
        }
    }

    public func showAllItems(_ categoryId: UUID) {
        showingAllIds.insert(categoryId)
    }

    public func visibleItems(for categoryId: UUID) -> [CleanupPreviewItem] {
        guard let idx = items.firstIndex(where: { $0.id == categoryId }) else { return [] }
        if showingAllIds.contains(categoryId) {
            return items[idx].children
        }
        return Array(items[idx].children.prefix(maxVisibleItems))
    }

    public func hasMoreItems(_ categoryId: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == categoryId }) else { return false }
        return items[idx].children.count > maxVisibleItems && !showingAllIds.contains(categoryId)
    }

    public func remainingCount(_ categoryId: UUID) -> Int {
        guard let idx = items.firstIndex(where: { $0.id == categoryId }) else { return 0 }
        return max(0, items[idx].children.count - maxVisibleItems)
    }

    // MARK: - Clear

    public func clear() {
        items = []
        selectedItemId = nil
        expandedCategoryIds = []
        showingAllIds = []
    }

    // MARK: - Private

    private func updateItemSelection(_ item: inout CleanupPreviewItem, isSelected: Bool) {
        guard item.isDeletable else { return }
        item.isSelected = isSelected
        for i in item.children.indices {
            updateItemSelection(&item.children[i], isSelected: isSelected)
        }
    }

    private static func selectedSizeBytes(for item: CleanupPreviewItem, seenPaths: inout Set<String>) -> Int64 {
        if item.children.isEmpty {
            guard item.isSelected else { return 0 }
            if let path = item.path {
                let normalized = normalizePath(path)
                guard seenPaths.insert(normalized).inserted else { return 0 }
            }
            return item.sizeBytes
        }

        return item.children.reduce(0) { $0 + selectedSizeBytes(for: $1, seenPaths: &seenPaths) }
    }

    private static func normalizePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (path as NSString).standardizingPath.replacingOccurrences(of: home, with: "~")
    }

    private static func selectedSizeBytes(for item: CleanupPreviewItem) -> Int64 {
        var seenPaths = Set<String>()
        return selectedSizeBytes(for: item, seenPaths: &seenPaths)
    }

    private func hasPreviewItem(for category: CleanupCategory) -> Bool {
        items.contains { item in
            category.previewLabels.contains(item.label)
        }
    }

    static func shortLabel(from path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = path.replacingOccurrences(of: "~", with: home)
        let components = (expanded as NSString).pathComponents
        if components.count >= 2 {
            return components.suffix(2).joined(separator: "/")
        }
        return (path as NSString).lastPathComponent
    }

    static func determineRisk(for label: String) -> OperationRisk {
        let l = label.lowercased()

        // Time Machine — moderate (user data, but safe to delete)
        if l.contains("time machine") || l.contains("tmutil") { return .moderate }
        // iOS backups — moderate (user data, re-downloadable from iCloud)
        if l.contains("ios backup") || l.contains("mobilesync") { return .moderate }
        // AI / LLM model stores — moderate (large user downloads, opt-in)
        if l.contains("ollama") || l.contains("huggingface") || l.contains("lm studio")
            || l.contains("lm-studio") || l.contains("/jan") || l.hasSuffix("/jan")
            || l.contains("ai models") || l.contains("mlx") || l.contains("whisper")
            || l.contains("vllm") || l.contains("torch") || l.contains("diffusionbee") {
            return .moderate
        }
        // Installers / large archives — moderate (user downloads, opt-in)
        if l.contains("installer") || l.hasSuffix(".dmg") || l.hasSuffix(".pkg")
            || l.hasSuffix(".iso") || l.contains("large file") {
            return .moderate
        }
        // Xcode / Android / Gradle — moderate
        if l.contains("xcode") || l.contains("android") || l.contains("gradle") { return .moderate }

        // All others — safe (auto-regenerated caches)
        return .safe
    }
}
