import XCTest
@testable import MacOSCleaner

final class AppResidualsOrphanEngineTests: XCTestCase {
    private var fileSystemContext: FileSystemContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        let home = fileSystemContext.homeDirectory
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        try super.tearDownWithError()
    }

    func test_extractBundleID_fromFolderName() async throws {
        let engine = AppResidualsOrphanEngine(fileSystemContext: fileSystemContext)
        let bundleIDFolder = fileSystemContext.homeDirectory.appendingPathComponent("com.example.uninstalledapp")
        let extracted = await engine.extractBundleID(from: bundleIDFolder)
        XCTAssertEqual(extracted, "com.example.uninstalledapp")
    }

    func test_extractBundleID_fromGroupFolderName() async throws {
        let engine = AppResidualsOrphanEngine(fileSystemContext: fileSystemContext)
        let groupFolder = fileSystemContext.homeDirectory.appendingPathComponent("group.com.example.sharedapp")
        let extracted = await engine.extractBundleID(from: groupFolder)
        XCTAssertEqual(extracted, "com.example.sharedapp")
    }

    func test_extractBundleID_fromContainerPlist() async throws {
        let tempDir = fileSystemContext.homeDirectory.appendingPathComponent("TestContainer_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let plistURL = tempDir.appendingPathComponent("Container.plist")
        let plistData: [String: Any] = ["MCMMetadataIdentifier": "com.test.orphanedcontainer"]
        let data = try PropertyListSerialization.data(fromPropertyList: plistData, format: .xml, options: 0)
        try data.write(to: plistURL)

        let engine = AppResidualsOrphanEngine(fileSystemContext: fileSystemContext)
        let extracted = await engine.extractBundleID(from: tempDir)
        XCTAssertEqual(extracted, "com.test.orphanedcontainer")
    }

    func test_scanOrphans_runsUnderIsolatedHomeWithoutCrashing() async throws {
        let uniqueID = "com.test.nonexistentapp_\(UUID().uuidString.prefix(8))"
        let orphanDir = fileSystemContext.homeDirectory.appendingPathComponent("Library/Caches/\(uniqueID)")
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try Data(repeating: 0xFF, count: 60 * 1024).write(to: orphanDir.appendingPathComponent("dummy.data"))

        let engine = AppResidualsOrphanEngine(fileSystemContext: fileSystemContext)
        // Two-clue threshold may exclude this fixture; assert scan stays under test home.
        let orphans = try await engine.scanOrphans()
        XCTAssertTrue(orphans.allSatisfy { fileSystemContext.isInsideAllowedRoots($0.url) })
    }

    func test_trashOrphans_withBypassTrash_permanentlyDeletes() async throws {
        let uniqueID = "com.test.bypassorphan_\(UUID().uuidString.prefix(8))"
        let orphanDir = fileSystemContext.homeDirectory.appendingPathComponent("Library/Caches/\(uniqueID)")
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)

        let dummyFile = orphanDir.appendingPathComponent("dummy.data")
        try Data(repeating: 0xBB, count: 60 * 1024).write(to: dummyFile)

        let orphanItem = OrphanItem(
            url: orphanDir,
            name: uniqueID,
            bundleID: uniqueID,
            sizeBytes: 60 * 1024,
            category: "Caches"
        )

        let engine = AppResidualsOrphanEngine(fileSystemContext: fileSystemContext)
        let freed = try await engine.trashOrphans([orphanItem], bypassTrash: true)

        XCTAssertGreaterThan(freed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDir.path))
    }
}
