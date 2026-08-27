import XCTest
@testable import MacOSCleaner

final class OrphanScannerTests: XCTestCase {
    var fileSystemContext: FileSystemContext!
    var testRoot: URL!
    var safetyManager: SafetyManager!
    var mockRunner: MockCommandRunner!
    var plistCache: PlistContentCache!
    var codesignCache: CodesignCache!
    var scanner: OrphanScanner!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        testRoot = fileSystemContext.homeDirectory
        safetyManager = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        mockRunner = MockCommandRunner()
        plistCache = PlistContentCache()
        codesignCache = CodesignCache()
        scanner = OrphanScanner(
            safetyManager: safetyManager,
            commandRunner: CommandRunner(),
            fileSystemContext: fileSystemContext,
            codesignCache: codesignCache,
            plistCache: plistCache
        )
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        scanner = nil
        safetyManager = nil
        fileSystemContext = nil
        testRoot = nil
        try super.tearDownWithError()
    }

    func testOrphanScannerInitialization() {
        XCTAssertNotNil(scanner)
    }

    func testOrphanItemModel_calculatesProperties() {
        let dummyURL = URL(fileURLWithPath: "/Users/test/Library/Preferences/com.example.orphan.plist")
        let item = OrphanItem(
            url: dummyURL,
            name: "Orphan",
            bundleID: "com.example.orphan",
            sizeBytes: 1024,
            category: "Preferences",
            evidence: [.bundleIDExact, .plistContent],
            confidence: .veryLikely,
            score: 80,
            isSelected: true
        )

        XCTAssertEqual(item.name, "Orphan")
        XCTAssertEqual(item.bundleID, "com.example.orphan")
        XCTAssertEqual(item.sizeBytes, 1024)
        XCTAssertEqual(item.category, "Preferences")
        XCTAssertEqual(item.confidence, .veryLikely)
        XCTAssertEqual(item.score, 80)
        XCTAssertTrue(item.isSelected)
        XCTAssertTrue(item.evidence.contains(.bundleIDExact))
    }

    func testOrphanScanner_scanOrphans_findsUnownedContainer() async throws {
        let containerDir = testRoot
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent("com.unknown.orphanapp", isDirectory: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        let sampleFile = containerDir.appendingPathComponent("data.bin")
        try Data(repeating: 0xAA, count: 8192).write(to: sampleFile)

        let orphans = try await scanner.scanOrphans()
        XCTAssertFalse(orphans.isEmpty, "Should find unowned container orphan")

        if let found = orphans.first(where: { $0.bundleID == "com.unknown.orphanapp" || $0.name == "Orphanapp" }) {
            XCTAssertEqual(found.category, "Containers")
            XCTAssertGreaterThanOrEqual(found.sizeBytes, 8192)
            XCTAssertTrue(found.evidence.contains(.container) || found.evidence.contains(.bundleIDExact))
            XCTAssertGreaterThanOrEqual(found.confidence, .possible)
        }
    }
}

