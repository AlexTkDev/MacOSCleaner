// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import XCTest
@testable import MacOSCleaner

final class CleanupHistoryTests: XCTestCase {
    
    func testCleanupRecordFormattedSize() {
        LanguageManager.testingLock.lock()
        defer {
            LanguageManager.shared.setLanguage(.english)
            LanguageManager.testingLock.unlock()
        }

        LanguageManager.shared.setLanguage(.english)
        let recordMB = CleanupRecord(freedBytes: 500 * 1024 * 1024)
        XCTAssertTrue(recordMB.formattedSize.hasPrefix("+"))
        XCTAssertTrue(recordMB.formattedSize.contains("MB"))
        
        let recordGB = CleanupRecord(freedBytes: Int64(17.28 * 1024 * 1024 * 1024))
        XCTAssertTrue(recordGB.formattedSize.hasPrefix("+"))
        XCTAssertTrue(recordGB.formattedSize.contains("GB"))

        LanguageManager.shared.setLanguage(.russian)
        XCTAssertTrue(recordGB.formattedSize.contains("ГБ"))
    }
    
    func testCleanupRecordMappingFromTransaction() {
        let devOp = OperationRecord(
            id: UUID(),
            itemPath: "/Users/test/Library/Developer/Xcode/DerivedData/app",
            status: "success",
            bytesFreed: 1024 * 1024 * 100
        )
        let txDev = CleanupTransaction(id: UUID(), timestamp: Date(), operations: [devOp])
        let recordDev = CleanupRecord(transaction: txDev)
        XCTAssertEqual(recordDev.category, .dev)
        XCTAssertEqual(recordDev.trigger, .manual)
        XCTAssertEqual(recordDev.freedBytes, 1024 * 1024 * 100)
        
        let mediaOp = OperationRecord(
            id: UUID(),
            itemPath: "/Users/test/Music/Cache",
            status: "success",
            bytesFreed: 2048
        )
        let txMedia = CleanupTransaction(id: UUID(), timestamp: Date(), operations: [mediaOp])
        let recordMedia = CleanupRecord(transaction: txMedia)
        XCTAssertEqual(recordMedia.category, .media)
        
        let cacheOp = OperationRecord(
            id: UUID(),
            itemPath: "/Users/test/Library/Caches/com.apple.Safari",
            status: "success",
            bytesFreed: 5000
        )
        let txCache = CleanupTransaction(id: UUID(), timestamp: Date(), operations: [cacheOp])
        let recordCache = CleanupRecord(transaction: txCache)
        XCTAssertEqual(recordCache.category, .caches)
        
        let generalOp = OperationRecord(
            id: UUID(),
            itemPath: "/Users/test/Downloads/installer.pkg",
            status: "success",
            bytesFreed: 10000
        )
        let txGeneral = CleanupTransaction(id: UUID(), timestamp: Date(), operations: [generalOp])
        let recordGeneral = CleanupRecord(transaction: txGeneral)
        XCTAssertEqual(recordGeneral.category, .general)
    }
    
    func testCleanupRecordsPrefixLimitOnDashboard() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let journalFile = tempDir.appendingPathComponent("transactions.jsonl")
        let journal = TransactionJournal(journalURL: journalFile)
        
        // Log 5 transactions
        for i in 1...5 {
            let op = OperationRecord(
                id: UUID(),
                itemPath: "/path/\(i)",
                status: "success",
                bytesFreed: Int64(i * 1000)
            )
            let tx = CleanupTransaction(id: UUID(), timestamp: Date().addingTimeInterval(Double(i * 60)), operations: [op])
            try await journal.log(transaction: tx)
        }
        
        let viewModel = await DashboardViewModel(journal: journal)
        await viewModel.refresh()
        
        let recent = await viewModel.recentRecords
        let all = await viewModel.allRecords
        
        XCTAssertEqual(recent.count, 3, "Dashboard should show at most 3 recent records")
        XCTAssertEqual(all.count, 5, "All records should retain complete history")
        XCTAssertEqual(recent.first?.freedBytes, 5000, "Most recent record should be first")
    }
    
    func testSortingAndFiltering() {
        let r1 = CleanupRecord(date: Date(timeIntervalSince1970: 1000), freedBytes: 1000, trigger: .manual, category: .general)
        let r2 = CleanupRecord(date: Date(timeIntervalSince1970: 2000), freedBytes: 5000, trigger: .automatic, category: .dev)
        let r3 = CleanupRecord(date: Date(timeIntervalSince1970: 3000), freedBytes: 2000, trigger: .manual, category: .media)
        let records = [r1, r2, r3]
        
        // Sort by date descending
        let dateDesc = records.sorted { $0.date > $1.date }
        XCTAssertEqual(dateDesc.map { $0.id }, [r3.id, r2.id, r1.id])
        
        // Sort by size descending
        let sizeDesc = records.sorted { $0.freedBytes > $1.freedBytes }
        XCTAssertEqual(sizeDesc.map { $0.id }, [r2.id, r3.id, r1.id])
        
        // Filter by category
        let devFiltered = records.filter { $0.category == .dev }
        XCTAssertEqual(devFiltered.count, 1)
        XCTAssertEqual(devFiltered.first?.id, r2.id)
    }
}
