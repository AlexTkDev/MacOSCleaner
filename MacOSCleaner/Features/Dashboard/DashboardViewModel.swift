import SwiftUI
import Foundation

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var totalDiskSpace: Int64 = 0
    @Published var freeDiskSpace: Int64 = 0
    @Published var totalFreedBytes: Int64 = 0
    @Published var cleanupCount: Int = 0
    @Published var recentTransactions: [CleanupTransaction] = []
    @Published var systemInfo: SystemInfo = .current
    
    private let journal: TransactionJournal
    
    init(journal: TransactionJournal) {
        self.journal = journal
    }
    
    func refresh() async {
        await fetchDiskUsage()
        await fetchHistory()
    }
    
    private func fetchDiskUsage() async {
        let fileManager = FileManager.default
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            totalDiskSpace = Int64(values.volumeTotalCapacity ?? 0)
            freeDiskSpace = Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            // Handle error
            print("Failed to fetch disk usage: \(error)")
        }
    }
    
    private func fetchHistory() async {
        do {
            let allTransactions = try await journal.loadAll()
            recentTransactions = Array(allTransactions.reversed().prefix(5))
            totalFreedBytes = allTransactions.reduce(0) { sum, transaction in
                sum + transaction.operations.reduce(0) { $0 + $1.bytesFreed }
            }
            cleanupCount = allTransactions.count
        } catch {
            print("Failed to load history: \(error)")
        }
    }
    
    var usedDiskSpace: Int64 {
        totalDiskSpace - freeDiskSpace
    }
    
    var usedDiskPercentage: Double {
        guard totalDiskSpace > 0 else { return 0 }
        return Double(usedDiskSpace) / Double(totalDiskSpace)
    }
}
