import XCTest
@testable import MacOSCleaner

final class FileSystemIsolationTests: XCTestCase {
    var fileSystemContext: FileSystemContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        try super.tearDownWithError()
    }

    func test_mutationOutsideIsolatedRootFailsClosed() async throws {
        let safety = SafetyManager(
            homeDirectory: fileSystemContext.homePath,
            fileSystemContext: fileSystemContext
        )
        let actor = FileCleanupActor(
            safetyManager: safety,
            fileSystemContext: fileSystemContext
        )

        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleaner-Outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let file = outside.appendingPathComponent("probe.txt")
        try Data("x".utf8).write(to: file)

        do {
            _ = try await actor.cleanContents(of: file.path, dryRun: false)
            XCTFail("Expected fail-closed guard outside test root")
        } catch let error as SafetyError {
            if case .protectedPath = error {
                // ok
            } else {
                XCTFail("Expected protectedPath, got \(error)")
            }
        } catch {
            XCTFail("Expected SafetyError, got \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Real/outside home must not be mutated")
    }

    func test_globExpansionRespectsMaxMatchesAndSkipsSymlinkDirs() throws {
        let home = fileSystemContext.homeDirectory
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)

        for i in 0..<40 {
            let dir = caches.appendingPathComponent("app-\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let link = caches.appendingPathComponent("link-dir", isDirectory: false)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: caches.appendingPathComponent("app-0")
        )

        let matches = CleanupPathExpander.expand(
            "~/Library/Caches/app-*",
            home: fileSystemContext.homePath,
            maxMatches: 10
        )
        XCTAssertEqual(matches.count, 10)

        let withLink = CleanupPathExpander.expand(
            "~/Library/Caches/*",
            home: fileSystemContext.homePath,
            maxMatches: 100
        )
        XCTAssertFalse(withLink.contains(link.path), "Symlink directories must not expand as glob bases")
    }

    func test_registryLookupPerformanceBudget() {
        let ids = Array(GeneratedCleanupPaths.registry.keys.prefix(50))
        XCTAssertFalse(ids.isEmpty)

        let start = ContinuousClock.now
        for _ in 0..<200 {
            for id in ids {
                _ = GeneratedCleanupPaths.appPaths(forBundleID: id)
            }
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, .milliseconds(200), "Registry lookup budget exceeded: \(elapsed)")
    }

    func test_cleanupEngineResultPartialFailureFlag() {
        let ok = CleanupEngineResult(label: "ok", freedMB: 1, removedCount: 2, skippedCount: 1, failedCount: 0)
        XCTAssertTrue(ok.isSuccess)
        XCTAssertFalse(ok.isPartialFailure)

        let partial = CleanupEngineResult(label: "partial", freedMB: 1, removedCount: 1, skippedCount: 0, failedCount: 3)
        XCTAssertTrue(partial.isPartialFailure)
        XCTAssertFalse(partial.isSuccess)
    }

    func test_emptyTrashWholesaleRefused() async {
        let trash = TrashManager(
            safetyManager: SafetyManager(
                homeDirectory: fileSystemContext.homePath,
                fileSystemContext: fileSystemContext
            )
        )
        do {
            _ = try await trash.emptyTrash()
            XCTFail("Wholesale emptyTrash must be refused")
        } catch is TrashError {
            // expected
        } catch {
            XCTFail("Expected TrashError, got \(error)")
        }
    }

    func test_oldBackupsReviewScanDoesNotTouchBackupsRoot() async throws {
        let home = fileSystemContext.homeDirectory
        let backupsRoot = home.appendingPathComponent("Backups", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)

        let keep = backupsRoot.appendingPathComponent("keep.backup")
        try Data(repeating: 2, count: 2048).write(to: keep)

        let old = desktop.appendingPathComponent("project.backup")
        try Data(repeating: 3, count: 4096).write(to: old)
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)

        final class PathBox: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [String] = []
            func append(_ value: String) {
                lock.lock(); defer { lock.unlock() }
                values.append(value)
            }
            func snapshot() -> [String] {
                lock.lock(); defer { lock.unlock() }
                return values
            }
        }
        let previewPaths = PathBox()
        let engine = CleanupEngine(fileSystemContext: fileSystemContext)
        _ = try await engine.run(categories: [.oldBackups], dryRun: true) { event in
            if case .fileItem(let path, _, _, _, _, _) = event {
                previewPaths.append(path)
            }
        }

        let paths = previewPaths.snapshot().map { ($0 as NSString).standardizingPath }
        let expected = (old.path as NSString).standardizingPath
        XCTAssertTrue(paths.contains(expected), "preview=\(paths)")
        let backupsPrefix = (backupsRoot.path as NSString).standardizingPath
        XCTAssertFalse(paths.contains(where: { $0.hasPrefix(backupsPrefix) }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }
}
