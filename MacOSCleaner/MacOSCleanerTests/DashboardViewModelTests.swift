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
    
    func testDiskCategoriesData() async {
        await viewModel.refresh()
        XCTAssertFalse(viewModel.isCategoriesLoading)
        XCTAssertEqual(viewModel.diskCategories.count, 6)
        
        let labels = Set(viewModel.diskCategories.map { $0.label })
        XCTAssertTrue(labels.contains("dashboard_radar_caches".localized))
        XCTAssertTrue(labels.contains("dashboard_radar_logs".localized))
        XCTAssertTrue(labels.contains("dashboard_radar_dev".localized))
        XCTAssertTrue(labels.contains("dashboard_radar_apps".localized))
        XCTAssertTrue(labels.contains("dashboard_radar_media".localized))
        XCTAssertTrue(labels.contains("dashboard_radar_other".localized))
    }

    func testCalculatePathSizeOffMain() async throws {
        let testDir = tempDir.appendingPathComponent("size_test_dir")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let file1 = testDir.appendingPathComponent("file1.dat")
        let file2 = testDir.appendingPathComponent("file2.dat")
        let data1 = Data(repeating: 0x41, count: 500)
        let data2 = Data(repeating: 0x42, count: 700)
        try data1.write(to: file1)
        try data2.write(to: file2)

        let dirSize = await DashboardViewModel.calculatePathSize(testDir.path)
        XCTAssertEqual(dirSize, 1200)

        let singleFileSize = await DashboardViewModel.calculatePathSize(file1.path)
        XCTAssertEqual(singleFileSize, 500)

        let nonexistentSize = await DashboardViewModel.calculatePathSize(testDir.appendingPathComponent("missing").path)
        XCTAssertEqual(nonexistentSize, 0)
    }
}
