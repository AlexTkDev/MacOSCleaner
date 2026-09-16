import XCTest
@testable import MacOSCleaner

final class UninstallerServiceTests: XCTestCase {
    var service: UninstallerService!

    override func setUp() async throws {
        service = UninstallerService()
    }

    func testScanState_initiallyDiscovered() {
        let app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp"
        )
        XCTAssertEqual(app.scanState, .discovered)
    }

    func testAppInfo_totalSize_withRelatedFiles() {
        var app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp",
            size: 100
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Caches/test.cache"), size: 50),
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Preferences/test.plist"), size: 30),
        ]
        XCTAssertEqual(app.totalSize, 180)
    }

    func testAppInfo_totalSize_ignoresDeselected() {
        var app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp",
            size: 100
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Caches/test.cache"), isSelected: false, size: 50),
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Preferences/test.plist"), size: 30),
        ]
        XCTAssertEqual(app.totalSize, 130)
    }

    func testConfidenceTier_comparable() {
        XCTAssertTrue(ConfidenceTier.possible < ConfidenceTier.veryLikely)
        XCTAssertTrue(ConfidenceTier.veryLikely < ConfidenceTier.guaranteed)
        XCTAssertTrue(ConfidenceTier.ignore < ConfidenceTier.possible)
    }

    func testRelatedFile_evidenceAndConfidence() {
        let file = UninstallerService.RelatedFile(
            url: URL(fileURLWithPath: "/Library/Caches/test.cache"),
            evidence: [.bundleIDExact, .teamID],
            confidence: .guaranteed
        )
        XCTAssertTrue(file.evidence.contains(.bundleIDExact))
        XCTAssertEqual(file.confidence, .guaranteed)
    }

    func testProtectedMailPaths() {
        let home = "/Users/test-fixture-home"
        XCTAssertTrue(UninstallerService.isProtectedMailPath("\(home)/Library/Mail", homeDirectory: home))
        XCTAssertTrue(UninstallerService.isProtectedMailPath("\(home)/Library/Mail/V10/INBOX.mbox", homeDirectory: home))
        XCTAssertTrue(UninstallerService.isProtectedMailPath("\(home)/Library/Containers/com.apple.mail/Data", homeDirectory: home))
        // Mail plugins are legitimate residuals
        XCTAssertFalse(UninstallerService.isProtectedMailPath("\(home)/Library/Mail/Bundles/SomePlugin.mailbundle", homeDirectory: home))
        XCTAssertFalse(UninstallerService.isProtectedMailPath("\(home)/Library/Application Support/SomeApp", homeDirectory: home))
    }

    func testPhysicalSize_sparseFile_reportsAllocatedNotLogical() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparseSizeTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1 GB logical, ~0 allocated (APFS sparse file, like OrbStack data.img.raw)
        let sparse = dir.appendingPathComponent("data.img.raw")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 1_073_741_824)
        try handle.close()

        let logical = (try? sparse.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        XCTAssertEqual(logical, 1_073_741_824)

        let physical = FileManager.default.getPhysicalDirectorySize(url: dir, excludedPaths: [])
        XCTAssertLessThan(physical, 50 * 1024 * 1024,
                          "Sparse file must be counted by allocated size, got \(physical)")

        let filePhysical = FileManager.default.getPhysicalDirectorySize(url: sparse, excludedPaths: [])
        XCTAssertLessThan(filePhysical, 50 * 1024 * 1024)
    }

    func testEvidence_category_mapping() {
        XCTAssertEqual(Evidence.bundleIDExact.category, .identity)
        XCTAssertEqual(Evidence.teamID.category, .signature)
        XCTAssertEqual(Evidence.launchAgent.category, .system)
        XCTAssertEqual(Evidence.packageReceipt.category, .metadata)
        XCTAssertEqual(Evidence.spotlight.category, .content)
        XCTAssertEqual(Evidence.parentDirectory.category, .graph)
        XCTAssertEqual(Evidence.launchServicesRegistered.category, .launchServices)
    }

    func testGroupKey_andMultiVersionAppInfo() {
        let app1 = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/opt/homebrew/Cellar/python@3.14/3.14.6/IDLE 3.app"),
            bundleID: "org.python.IDLE",
            name: "IDLE 3",
            size: 200,
            version: "3.14.6"
        )
        let app2 = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/opt/homebrew/Cellar/python@3.12/3.12.13/IDLE 3.app"),
            bundleID: "org.python.IDLE",
            name: "IDLE 3",
            size: 150,
            version: "3.12.13"
        )

        XCTAssertEqual(UninstallerService.groupKey(for: app1), UninstallerService.groupKey(for: app2))

        let grouped = UninstallerService.AppInfo(
            url: app1.url,
            bundleID: app1.bundleID,
            name: app1.name,
            size: 350,
            version: "3.14.6, 3.12.13",
            versions: [app1, app2]
        )

        XCTAssertTrue(grouped.isGrouped)
        XCTAssertEqual(grouped.versions.count, 2)
        XCTAssertEqual(grouped.totalSize, 350)
    }

    // MARK: - Trash & Bypass Trash Behavior

    func testUninstall_bypassTrash_deletesDirectly_preservesThirdPartyTrash() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer {
            if let root = ctx.allowedRoots.first {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trashDir = ctx.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let testService = UninstallerService(safetyManager: safety, trashManager: trash)

        // Setup app & related files
        let appDir = ctx.homeDirectory.appendingPathComponent("Applications/Demo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appBinary = appDir.appendingPathComponent("Demo")
        try "binary".data(using: .utf8)!.write(to: appBinary)

        let cacheDir = ctx.homeDirectory.appendingPathComponent("Library/Caches/com.demo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent("cache.db")
        try "cache".data(using: .utf8)!.write(to: cacheFile)

        // Setup third-party file in trash
        let finderTrashFile = trashDir.appendingPathComponent("user_important_doc.pdf")
        try "important".data(using: .utf8)!.write(to: finderTrashFile)

        var app = UninstallerService.AppInfo(
            url: appDir,
            bundleID: "com.demo.app",
            name: "Demo"
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: cacheFile, isSelected: true, size: 5)
        ]

        _ = try await testService.uninstall(app: app, bypassTrash: true, emptyTrashImmediately: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: appDir.path), "App should be removed directly")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path), "Related file should be removed directly")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderTrashFile.path), "Finder trash files must never be touched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("Demo.app").path), "Should not be moved to trash")
    }

    func testUninstall_emptyTrashImmediately_deletesOwnFiles_preservesThirdPartyTrash() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer {
            if let root = ctx.allowedRoots.first {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trashDir = ctx.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let testService = UninstallerService(safetyManager: safety, trashManager: trash)

        let appDir = ctx.homeDirectory.appendingPathComponent("Applications/Demo2.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appBinary = appDir.appendingPathComponent("Demo2")
        try "binary".data(using: .utf8)!.write(to: appBinary)

        let finderTrashFile = trashDir.appendingPathComponent("existing_trash_file.txt")
        try "dont_delete_me".data(using: .utf8)!.write(to: finderTrashFile)

        let app = UninstallerService.AppInfo(
            url: appDir,
            bundleID: "com.demo2.app",
            name: "Demo2"
        )

        _ = try await testService.uninstall(app: app, bypassTrash: false, emptyTrashImmediately: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: appDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("Demo2.app").path),
                       "App should be removed immediately from Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderTrashFile.path),
                      "Finder trash files must never be touched by emptyTrashImmediately")
    }

    func testUninstall_defaultTrash_movesToTrash_preservesThirdPartyTrash() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer {
            if let root = ctx.allowedRoots.first {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trashDir = ctx.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let testService = UninstallerService(safetyManager: safety, trashManager: trash)

        let appDir = ctx.homeDirectory.appendingPathComponent("Applications/Demo3.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appBinary = appDir.appendingPathComponent("Demo3")
        try "binary".data(using: .utf8)!.write(to: appBinary)

        let finderTrashFile = trashDir.appendingPathComponent("existing_trash_file.txt")
        try "dont_delete_me".data(using: .utf8)!.write(to: finderTrashFile)

        let app = UninstallerService.AppInfo(
            url: appDir,
            bundleID: "com.demo3.app",
            name: "Demo3"
        )

        _ = try await testService.uninstall(app: app, bypassTrash: false, emptyTrashImmediately: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: appDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("Demo3.app").path),
                      "App should remain in Trash when emptyTrashImmediately is false")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderTrashFile.path),
                      "Finder trash files must never be touched")
    }
}
