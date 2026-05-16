import XCTest
@testable import MacOSCleaner

final class TransactionJournalTests: XCTestCase {
    var journal: TransactionJournal!
    var tempJournalURL: URL!
    
    override func setUp() {
        super.setUp()
        tempJournalURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_journal_\(UUID().uuidString).jsonl")
        journal = TransactionJournal(journalURL: tempJournalURL)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempJournalURL)
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
}
