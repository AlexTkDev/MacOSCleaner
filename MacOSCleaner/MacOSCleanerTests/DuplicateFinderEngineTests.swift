// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import XCTest
@testable import MacOSCleaner

final class DuplicateFinderEngineTests: XCTestCase {
    var engine: DuplicateFinderEngine!
    var tempDirectory: URL!

    override func setUp() async throws {
        engine = DuplicateFinderEngine()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleanerTests_Duplicates_\(UUID().uuidString)", isDirectory: true)

        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testDuplicateDetectionAndDifferentiation() async throws {
        let contentA = Data(repeating: 0x41, count: 8192) // 8KB of 'A'
        let contentB = Data(repeating: 0x42, count: 8192) // 8KB of 'B' (same size, different header/full hash)

        let file1 = tempDirectory.appendingPathComponent("copy1.bin")
        let file2 = tempDirectory.appendingPathComponent("copy2.bin")
        let file3 = tempDirectory.appendingPathComponent("different.bin")

        try contentA.write(to: file1)
        try contentA.write(to: file2)
        try contentB.write(to: file3)

        let groups = try await engine.scan(directory: tempDirectory, minSizeBytes: 1024)

        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.items.count, 2)

        let fileNames = Set(group.items.map(\.name))
        XCTAssertTrue(fileNames.contains("copy1.bin"))
        XCTAssertTrue(fileNames.contains("copy2.bin"))
        XCTAssertFalse(fileNames.contains("different.bin"))
    }

    func testSmartSelectStrategies() async throws {
        let now = Date()
        let item1 = DuplicateFileItem(url: tempDirectory.appendingPathComponent("f1.txt"), sizeBytes: 2048, modificationDate: now.addingTimeInterval(-3600), isSelected: false)
        let item2 = DuplicateFileItem(url: tempDirectory.appendingPathComponent("f2.txt"), sizeBytes: 2048, modificationDate: now, isSelected: false)

        let group = DuplicateGroup(fileSize: 2048, hashValue: "test_hash", items: [item1, item2])

        let keepOldest = await engine.applySmartSelect(groups: [group], strategy: .keepOldest).first!
        XCTAssertFalse(keepOldest.items.first(where: { $0.name == "f1.txt" })!.isSelected)
        XCTAssertTrue(keepOldest.items.first(where: { $0.name == "f2.txt" })!.isSelected)

        let keepNewest = await engine.applySmartSelect(groups: [group], strategy: .keepNewest).first!
        XCTAssertTrue(keepNewest.items.first(where: { $0.name == "f1.txt" })!.isSelected)
        XCTAssertFalse(keepNewest.items.first(where: { $0.name == "f2.txt" })!.isSelected)

        let selectAll = await engine.applySmartSelect(groups: [group], strategy: .selectAll).first!
        XCTAssertTrue(selectAll.items.allSatisfy(\.isSelected))

        let deselectAll = await engine.applySmartSelect(groups: [group], strategy: .deselectAll).first!
        XCTAssertTrue(deselectAll.items.allSatisfy({ !$0.isSelected }))
    }
}
