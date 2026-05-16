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
    
    public struct CleanupPreviewItem: Identifiable, Sendable {
        public let id = UUID()
        public let label: String
        public let sizeMB: Int
        public let risk: OperationRisk
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
                items = []
                
                let stream = adapter.runCleanup(dryRun: true)
                for try await event in stream {
                    switch event {
                    case .step(let current, let total, let title):
                        self.currentStep = current
                        self.totalSteps = total
                        self.stepTitle = title
                    case .preview(let label, let size):
                        let risk = determineRisk(for: label)
                        self.items.append(CleanupPreviewItem(label: label, sizeMB: size, risk: risk))
                    case .result: break
                    }
                }
                
                try stateMachine.transition(to: .preview)
            } catch {
                try? stateMachine.transition(to: .failed)
            }
        }
    }
    
    @MainActor
    public func executeCleanup() {
        Task {
            do {
                try stateMachine.transition(to: .executing)
                totalFreedMB = 0
                
                let stream = adapter.runCleanup(dryRun: false)
                var records: [OperationRecord] = []
                
                for try await event in stream {
                    switch event {
                    case .step(let current, let total, let title):
                        self.currentStep = current
                        self.totalSteps = total
                        self.stepTitle = title
                    case .result(let label, let freed):
                        self.totalFreedMB += freed
                        records.append(OperationRecord(id: UUID(), itemPath: label, status: "success", bytesFreed: Int64(freed * 1024 * 1024)))
                    case .preview: break
                    }
                }
                
                let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: records)
                try await journal.log(transaction: transaction)
                
                try stateMachine.transition(to: .completed)
            } catch {
                try? stateMachine.transition(to: .failed)
            }
        }
    }
    
    @MainActor
    public func reset() {
        stateMachine.reset()
        items = []
        totalFreedMB = 0
        currentStep = 0
        stepTitle = ""
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
