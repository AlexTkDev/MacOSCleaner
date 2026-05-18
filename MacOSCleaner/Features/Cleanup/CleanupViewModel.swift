import Foundation
import Observation

@Observable
public final class CleanupViewModel {
    private let stateMachine = CleanupStateMachine()
    private let adapter: ShellCleanupAdapter
    private let journal: TransactionJournal
    
    public var state: CleanupState { stateMachine.state }
    public var currentStep: Int = 0
    public var totalSteps: Int = 1
    public var stepTitle: String = ""
    public var items: [CleanupPreviewItem] = []
    public var totalFreedMB: Int = 0
    public var cleanedItems: [CleanupResultItem] = []
    public var options = ShellCleanupAdapter.CleanupOptions()
    
    public struct CleanupResultItem: Identifiable, Sendable {
        public let id: UUID = UUID()
        public let label: String
        public let freedMB: Int
    }
    public var lastError: String? = nil
    public var scriptLogs: [String] = []
    public var selectedItemId: UUID? = nil
    
    public struct CleanupPreviewItem: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let label: String
        public var sizeMB: Int
        public let risk: OperationRisk
        public var isSelected: Bool
        public let isDeletable: Bool
        public let description: String?
        public var children: [CleanupPreviewItem]
        
        public init(id: UUID = UUID(), label: String, sizeMB: Int, risk: OperationRisk, isSelected: Bool = true, isDeletable: Bool, description: String? = nil, children: [CleanupPreviewItem] = []) {
            self.id = id
            self.label = label
            self.sizeMB = sizeMB
            self.risk = risk
            self.isSelected = isSelected
            self.isDeletable = isDeletable
            self.description = description
            self.children = children
        }
        
        public static func == (lhs: CleanupPreviewItem, rhs: CleanupPreviewItem) -> Bool {
            lhs.id == rhs.id && 
            lhs.sizeMB == rhs.sizeMB && 
            lhs.isSelected == rhs.isSelected && 
            lhs.children == rhs.children &&
            lhs.description == rhs.description
        }
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
            print("[debug] Total selected calculation (\(total)MB):")
            logs.forEach { print("  - \($0)") }
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
    
    public func updateAllSelection(isSelected: Bool) {
        for i in items.indices {
            updateItemSelection(&items[i], isSelected: isSelected)
        }
    }
    
    private func updateItemSelection(_ item: inout CleanupPreviewItem, isSelected: Bool) {
        guard item.isDeletable else { return }
        item.isSelected = isSelected
        for i in item.children.indices {
            updateItemSelection(&item.children[i], isSelected: isSelected)
        }
    }
    
    public init(adapter: ShellCleanupAdapter, journal: TransactionJournal) {
        self.adapter = adapter
        self.journal = journal
    }
    
    @MainActor
    public func startScan() {
        Task {
            do {
                try stateMachine.transition(to: .scanning)
                self.items = []
                self.lastError = nil
                self.scriptLogs = []
                self.selectedItemId = nil
                
                let stream = adapter.runCleanup(scanOnly: true, options: options)
                for try await event in stream {
                    switch event {
                    case .step(let current, let total, let title):
                        self.currentStep = current
                        self.totalSteps = total
                        self.stepTitle = title
                    case .preview(let label, let size, let deletable, let parentName, let description):
                        print("[debug] Preview event: label=\(label), size=\(size), parent=\(parentName ?? "none"), description=\(description ?? "none")")
                        let risk = deletable ? determineRisk(for: label) : .protected
                        let newItem = CleanupPreviewItem(
                            label: label,
                            sizeMB: size,
                            risk: risk,
                            isSelected: deletable,
                            isDeletable: deletable,
                            description: description
                        )
                        
                        if let parentName = parentName, !parentName.isEmpty {
                            // Ищем родителя или создаем его
                            if let idx = self.items.firstIndex(where: { $0.label == parentName }) {
                                if !self.items[idx].children.contains(where: { $0.label == label }) {
                                    self.items[idx].children.append(newItem)
                                    // Размер родителя - сумма детей
                                    self.items[idx].sizeMB = self.items[idx].children.reduce(0) { $0 + $1.sizeMB }
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
                                self.items.append(parent)
                            }
                        } else {
                            // Если такой рутовый элемент уже есть (например, создан как родитель для ребенка),
                            // то не добавляем его снова, а просто обновляем размер если нужно.
                            if let idx = self.items.firstIndex(where: { $0.label == label }) {
                                // Если у него уже есть дети, значит размер и так актуален (сумма детей).
                                // Если нет, берем максимальный из размеров.
                                if self.items[idx].children.isEmpty {
                                    self.items[idx].sizeMB = max(self.items[idx].sizeMB, size)
                                }
                            } else {
                                self.items.append(newItem)
                            }
                        }
                    case .log(let message):
                        self.scriptLogs.append(message)
                    case .result: break
                    }
                }
                
                try stateMachine.transition(to: .preview)
            } catch let error {
                self.lastError = error.localizedDescription
                try? stateMachine.transition(to: .failed)
            }
        }
    }
    
    @MainActor
    public func executeCleanup() {
        Task {
            do {
                try stateMachine.transition(to: .executing)
                self.totalFreedMB = 0
                self.cleanedItems = []
                self.lastError = nil
                self.scriptLogs = []
                
                let selectedPaths = items.filter { $0.isSelected }.map { $0.label }
                let stream = adapter.runCleanup(options: options, selectedPaths: selectedPaths)
                var records: [OperationRecord] = []
                
                for try await event in stream {
                    switch event {
                    case .step(let current, let total, let title):
                        self.currentStep = current
                        self.totalSteps = total
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
                
                let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: records)
                try await journal.log(transaction: transaction)
                
                try stateMachine.transition(to: .completed)
            } catch let error {
                self.lastError = error.localizedDescription
                try? stateMachine.transition(to: .failed)
            }
        }
    }
    
    @MainActor
    public func reset() {
        stateMachine.reset()
        items = []
        cleanedItems = []
        totalFreedMB = 0
        currentStep = 0
        stepTitle = ""
        lastError = nil
        scriptLogs = []
    }
    
    private func determineRisk(for label: String) -> OperationRisk {
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
