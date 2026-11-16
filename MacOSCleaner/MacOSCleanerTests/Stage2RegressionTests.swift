import XCTest
@testable import MacOSCleaner

final class Stage2RegressionTests: XCTestCase {
    func test_updateChecker_isNewer() {
        XCTAssertTrue(UpdateChecker.isNewer("2.4.0", than: "2.3.0"))
        XCTAssertTrue(UpdateChecker.isNewer("v2.4.0", than: "2.3.0"))
        XCTAssertFalse(UpdateChecker.isNewer("2.3.0", than: "2.3.0"))
        XCTAssertFalse(UpdateChecker.isNewer("2.2.9", than: "2.3.0"))
    }

    func test_dockTileManager_filterPersistentApps_byURLAndUniqueBundleID() {
        let entries: [[String: Any]] = [
            [
                "tile-data": [
                    "bundle-identifier": "com.example.AppA",
                    "file-data": ["_CFURLString": "file:///Applications/AppA.app/"]
                ]
            ],
            [
                "tile-data": [
                    "bundle-identifier": "com.example.Dup",
                    "file-data": ["_CFURLString": "file:///Applications/Dup1.app/"]
                ]
            ],
            [
                "tile-data": [
                    "bundle-identifier": "com.example.Dup",
                    "file-data": ["_CFURLString": "file:///Applications/Dup2.app/"]
                ]
            ],
        ]

        // Match by exact URL
        let res1 = DockTileManager.filterPersistentApps(
            entries,
            appURL: URL(fileURLWithPath: "/Applications/AppA.app"),
            bundleID: "com.example.Other"
        )
        XCTAssertEqual(res1.removedCount, 1)
        XCTAssertEqual(res1.updated.count, 2)

        // Match by unique bundleID when URL differs
        let res2 = DockTileManager.filterPersistentApps(
            entries,
            appURL: URL(fileURLWithPath: "/Users/test/Applications/AppA.app"),
            bundleID: "com.example.AppA"
        )
        XCTAssertEqual(res2.removedCount, 1)

        // Ambiguous bundleID (>1) does not match by bundleID alone
        let res3 = DockTileManager.filterPersistentApps(
            entries,
            appURL: URL(fileURLWithPath: "/Users/test/Applications/Dup3.app"),
            bundleID: "com.example.Dup"
        )
        XCTAssertEqual(res3.removedCount, 0)
        XCTAssertEqual(res3.updated.count, 3)
    }

    func test_codeSignatureInfo_adHocNotAppleSigned() async {
        let adHocRunner = MockCommandRunner()
        adHocRunner.runHandler = { _, _ in
            CommandResult(
                stdout: "",
                stderr: "Executable=/tmp/foo\nIdentifier=foo\nSignature=adhoc\n",
                exitCode: 0
            )
        }
        let info = await CodeSignatureInfo.check(path: "/tmp/foo", commandRunner: adHocRunner)
        XCTAssertTrue(info.isSigned)
        XCTAssertFalse(info.isAppleSigned)

        let appleRunner = MockCommandRunner()
        appleRunner.runHandler = { _, _ in
            CommandResult(
                stdout: "",
                stderr: "Authority=Software Signing\nAuthority=Apple Code Signing Certification Authority\n",
                exitCode: 0
            )
        }
        let appleInfo = await CodeSignatureInfo.check(path: "/System/Applications/Notes.app", commandRunner: appleRunner)
        XCTAssertTrue(appleInfo.isSigned)
        XCTAssertTrue(appleInfo.isAppleSigned)
    }

    func test_safetyManager_blocksSecretFilesUnderCleanup() throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)

        let secretNames = [".env", ".env.local", ".npmrc", ".yarnrc", ".pypirc", "credentials.toml", ".claude.json"]
        for name in secretNames {
            let url = ctx.homeDirectory.appendingPathComponent("Library/Caches/\(name)")
            XCTAssertThrowsError(try safety.validate(url: url, policy: .cleanup), "Expected \(name) to be protected")
        }
    }

    func test_fileCleanupActor_movesToTrashByDefault() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }

        let trashDir = ctx.allowedRoots[0].appendingPathComponent("TestTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

        let cacheDir = ctx.homeDirectory.appendingPathComponent("Library/Caches/com.test.app", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let targetFile = cacheDir.appendingPathComponent("cache.bin")
        try Data("hello".utf8).write(to: targetFile)

        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let actor = FileCleanupActor(safetyManager: safety, fileSystemContext: ctx, trashManager: trash)

        let result = try await actor.cleanContents(of: cacheDir.path, dryRun: false, bypassTrash: false)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile.path))

        let trashedContents = try FileManager.default.contentsOfDirectory(atPath: trashDir.path)
        XCTAssertEqual(trashedContents.count, 1)
    }
}
