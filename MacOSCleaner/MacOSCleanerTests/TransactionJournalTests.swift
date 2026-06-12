import XCTest
@testable import MacOSCleaner

final class TransactionJournalTests: XCTestCase {
    var journal: TransactionJournal!
    var tempJournalURL: URL!
    var tempArchiveDirectory: URL!
    
    override func setUp() {
        super.setUp()
        tempJournalURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_journal_\(UUID().uuidString).jsonl")
        tempArchiveDirectory = tempJournalURL.deletingLastPathComponent().appendingPathComponent("archives_\(UUID().uuidString)", isDirectory: true)
        journal = TransactionJournal(journalURL: tempJournalURL)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempJournalURL)
        try? FileManager.default.removeItem(at: tempArchiveDirectory)
        super.tearDown()
    }
    
    func testLogAndLoad() async throws {
        let transaction1 = CleanupTransaction(
            id: UUID(),
            timestamp: Date(),
            operations: [
                OperationRecord(id: UUID(), itemPath: "/path/1", status: "success", bytesFreed: 100)
            ]
        )
        
        let transaction2 = CleanupTransaction(
            id: UUID(),
            timestamp: Date().addingTimeInterval(1),
            operations: [
                OperationRecord(id: UUID(), itemPath: "/path/2", status: "success", bytesFreed: 200)
            ]
        )
        
        try await journal.log(transaction: transaction1)
        try await journal.log(transaction: transaction2)
        
        let all = try await journal.loadAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].id, transaction1.id)
        XCTAssertEqual(all[1].id, transaction2.id)
        XCTAssertEqual(all[1].operations[0].itemPath, "/path/2")
    }
    
    func testLoadEmptyJournal() async throws {
        let all = try await journal.loadAll()
        XCTAssertTrue(all.isEmpty)
    }
    
    func testJournalSize() async throws {
        let initialSize = try await journal.journalSize()
        XCTAssertEqual(initialSize, 0)
        
        let transaction = CleanupTransaction(
            id: UUID(),
            timestamp: Date(),
            operations: [
                OperationRecord(id: UUID(), itemPath: "/path/1", status: "success", bytesFreed: 100)
            ]
        )
        
        try await journal.log(transaction: transaction)
        
        let afterWriteSize = try await journal.journalSize()
        XCTAssertGreaterThan(afterWriteSize, 0, "Journal should have content after writing")
    }
    
    func testClear() async throws {
        let transaction = CleanupTransaction(
            id: UUID(),
            timestamp: Date(),
            operations: [
                OperationRecord(id: UUID(), itemPath: "/path/1", status: "success", bytesFreed: 100)
            ]
        )
        
        try await journal.log(transaction: transaction)
        let sizeBeforeClear = try await journal.journalSize()
        XCTAssertGreaterThan(sizeBeforeClear, 0, "Journal should have content before clear")
        
        try await journal.clear()
        let sizeAfterClear = try await journal.journalSize()
        XCTAssertEqual(sizeAfterClear, 0, "Journal should be empty after clear")
    }
    
    func testClearAll() async throws {
        let transaction = CleanupTransaction(
            id: UUID(),
            timestamp: Date(),
            operations: [
                OperationRecord(id: UUID(), itemPath: "/path/1", status: "success", bytesFreed: 100)
            ]
        )
        
        try await journal.log(transaction: transaction)
        try await journal.clearAll()
        
        let all = try await journal.loadAll()
        XCTAssertTrue(all.isEmpty)
    }
}
