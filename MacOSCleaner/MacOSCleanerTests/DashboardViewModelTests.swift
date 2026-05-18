import XCTest
@testable import MacOSCleaner

@MainActor
final class DashboardViewModelTests: XCTestCase {
    var viewModel: DashboardViewModel!
    var journal: TransactionJournal!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let journalURL = tempDir.appendingPathComponent("test.jsonl")
        journal = TransactionJournal(journalURL: journalURL)
        viewModel = DashboardViewModel(journal: journal)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        viewModel = nil
        journal = nil
        try await super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(viewModel.totalFreedBytes, 0)
        XCTAssertEqual(viewModel.cleanupCount, 0)
        XCTAssertTrue(viewModel.recentTransactions.isEmpty)
    }
    
    func testFetchHistory() async throws {
        // Given
        let record = OperationRecord(id: UUID(), itemPath: "/tmp/test", status: "success", bytesFreed: 1024)
        let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: [record])
        try await journal.log(transaction: transaction)
        
        // When
        await viewModel.refresh()
        
        // Then
        XCTAssertEqual(viewModel.cleanupCount, 1)
        XCTAssertEqual(viewModel.totalFreedBytes, 1024)
        XCTAssertEqual(viewModel.recentTransactions.count, 1)
        XCTAssertEqual(viewModel.recentTransactions.first?.id, transaction.id)
    }
    
    func testDiskUsage() async {
        await viewModel.refresh()
        XCTAssertGreaterThan(viewModel.totalDiskSpace, 0)
        XCTAssertGreaterThan(viewModel.freeDiskSpace, 0)
        XCTAssertGreaterThanOrEqual(viewModel.usedDiskPercentage, 0)
        XCTAssertLessThanOrEqual(viewModel.usedDiskPercentage, 1.0)
    }
}
