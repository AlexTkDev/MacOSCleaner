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
    
    func testClear() async throws {
        let transaction = CleanupTransaction(
            id: UUID(),
            timestamp: Date(),
            operations: [
                OperationRecord(id: UUID(), itemPath: "/path/1", status: "success", bytesFreed: 100)
            ]
        )
        
        try await journal.log(transaction: transaction)
        let loadedBeforeClear = try await journal.loadAll()
        XCTAssertEqual(loadedBeforeClear.count, 1)
        
        try await journal.clear()
        let loadedAfterClear = try await journal.loadAll()
        XCTAssertTrue(loadedAfterClear.isEmpty, "Journal should be empty after clear")
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

    func testDecodeIfPresentBackwardCompatibility() async throws {
        let legacyID = UUID()
        let opID = UUID()
        let legacyJSON = """
        {"id":"\(legacyID.uuidString)","timestamp":0,"operations":[{"id":"\(opID.uuidString)","itemPath":"App caches","status":"success","bytesFreed":4096}]}
        """
        let modernID = UUID()
        let modernOpID = UUID()
        let modernJSON = """
        {"id":"\(modernID.uuidString)","timestamp":10,"trigger":"automatic","operations":[{"id":"\(modernOpID.uuidString)","itemPath":"Xcode","status":"partial","bytesFreed":8192,"categoryCode":"xcode","deletionMode":"permanent","skipped":2,"failed":1}]}
        """
        try (legacyJSON + "\n" + modernJSON + "\n").write(to: tempJournalURL, atomically: true, encoding: .utf8)

        let loaded = try await journal.loadAll()
        XCTAssertEqual(loaded.count, 2)

        XCTAssertNil(loaded[0].trigger)
        XCTAssertNil(loaded[0].operations[0].categoryCode)
        XCTAssertNil(loaded[0].operations[0].deletionMode)
        XCTAssertNil(loaded[0].operations[0].skipped)
        XCTAssertNil(loaded[0].operations[0].failed)

        XCTAssertEqual(loaded[1].trigger, .automatic)
        XCTAssertEqual(loaded[1].operations[0].categoryCode, "xcode")
        XCTAssertEqual(loaded[1].operations[0].deletionMode, "permanent")
        XCTAssertEqual(loaded[1].operations[0].skipped, 2)
        XCTAssertEqual(loaded[1].operations[0].failed, 1)
    }
}
