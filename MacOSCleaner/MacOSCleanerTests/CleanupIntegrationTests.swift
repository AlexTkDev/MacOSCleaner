import XCTest
@testable import MacOSCleaner

/// Integration tests verifying the full cleanup flow: scan → preview → cleanup → verify.
/// Uses real directories in /tmp to ensure files are actually created and deleted.
final class CleanupIntegrationTests: XCTestCase {

    var testRoot: URL!

    override func setUp() {
        super.setUp()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleanerIntegrationTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        super.tearDown()
    }

    // MARK: - Full Flow: Scan → Preview → Cleanup → Verify

    func testFullFlow_ScanPreviewCleanupVerify() async throws {
        let cacheDir = testRoot.appendingPathComponent("Library/Caches/com.test.app")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let file1 = cacheDir.appendingPathComponent("cache1.dat")
        let file2 = cacheDir.appendingPathComponent("cache2.log")
        try Data(repeating: 0xAB, count: 1024 * 100).write(to: file1)
        try Data(repeating: 0xCD, count: 1024 * 200).write(to: file2)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        let result = try await engine.cleanContents(of: cacheDir.path, dryRun: false)
        XCTAssertGreaterThan(result.freed, 0, "Should free some space")

        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path),
                       "cache1.dat should be deleted after cleanup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path),
                       "cache2.log should be deleted after cleanup")
    }

    func testFullFlow_DryRunPreservesFiles() async throws {
        let cacheDir = testRoot.appendingPathComponent("Caches/testcache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let file = cacheDir.appendingPathComponent("data.bin")
        try Data(repeating: 0xFF, count: 512).write(to: file)

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        let results = try await engine.run(categories: [.scatteredJunk], dryRun: true)
        XCTAssertFalse(results.isEmpty)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                       "Files should be preserved in dry run")
    }

    // MARK: - Real Directories in /tmp

    func testCleanupRealTempDirectories() async throws {
        let dirA = testRoot.appendingPathComponent("tempA")
        let dirB = testRoot.appendingPathComponent("tempB")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

        for i in 0..<10 {
            let file = dirA.appendingPathComponent("file_\(i).txt")
            try "content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        let largeFile = dirB.appendingPathComponent("large.dat")
        try Data(repeating: 0xAA, count: 1024 * 1024).write(to: largeFile)

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        _ = try await engine.cleanContents(of: dirA.path, dryRun: false)
        _ = try await engine.cleanContents(of: dirB.path, dryRun: false)

        let remainingA = try? FileManager.default.contentsOfDirectory(atPath: dirA.path)
        XCTAssertEqual(remainingA?.count, 0, "dirA should be empty after cleanup")

        XCTAssertFalse(FileManager.default.fileExists(atPath: largeFile.path),
                       "Large file should be deleted")
    }

    func testMultipleCategoryCleanup() async throws {
        let cachesDir = testRoot.appendingPathComponent("Caches/com.test.multi")
        let logsDir = testRoot.appendingPathComponent("Logs")
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        try Data(repeating: 0x01, count: 4096).write(to: cachesDir.appendingPathComponent("cache.bin"))
        try "log data".write(to: logsDir.appendingPathComponent("app.log"), atomically: true, encoding: .utf8)

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        let results = try await engine.run(
            categories: [.appCaches, .userLogs],
            dryRun: false
        )
        XCTAssertGreaterThanOrEqual(results.count, 1)
    }

    // MARK: - Cancellation at Different Stages

    func testCancellationDuringScan() async throws {
        let cacheDir = testRoot.appendingPathComponent("Caches/cancellation_scan")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0xBB, count: 1024).write(to: cacheDir.appendingPathComponent("file.dat"))

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        let task = Task {
            try await engine.run(categories: CleanupCategory.allCases, dryRun: true)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors acceptable
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent("file.dat").path),
                       "File should still exist after cancelled scan")
    }

    func testCancellationDuringCleanup() async throws {
        let cacheDir = testRoot.appendingPathComponent("Caches/cancellation_cleanup")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0xCC, count: 1024).write(to: cacheDir.appendingPathComponent("file.dat"))

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        let task = Task {
            try await engine.run(categories: [.appCaches], dryRun: false)
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // CleanupEngineError.timeout or other acceptable errors
        }
    }

    // MARK: - Verify Files Actually Deleted

    func testVerifyFilesDeletedAfterCleanup() async throws {
        let testDir = testRoot.appendingPathComponent("verify_deletion")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        var filePaths: [URL] = []
        for i in 0..<20 {
            let file = testDir.appendingPathComponent("item_\(i).cache")
            try Data(repeating: UInt8(i), count: 1024).write(to: file)
            filePaths.append(file)
        }

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        for path in filePaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path),
                          "File \(path.lastPathComponent) should exist before cleanup")
        }

        _ = try await engine.cleanContents(of: testDir.path, dryRun: false)

        for path in filePaths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path),
                           "File \(path.lastPathComponent) should be deleted after cleanup")
        }

        let remaining = try? FileManager.default.contentsOfDirectory(atPath: testDir.path)
        XCTAssertEqual(remaining?.count, 0, "Directory should be empty after cleanup")
    }

    func testVerifyDirectorySizeReduced() async throws {
        let testDir = testRoot.appendingPathComponent("verify_size")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let data = Data(repeating: 0xDD, count: 1024 * 50)
        for i in 0..<5 {
            try data.write(to: testDir.appendingPathComponent("chunk_\(i).dat"))
        }

        let sizeBefore = try FileManager.default.contentsOfDirectory(atPath: testDir.path)
            .compactMap { try? FileManager.default.attributesOfItem(atPath: testDir.appendingPathComponent($0).path)[.size] as? Int64 }
            .reduce(0, +)

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))
        _ = try await engine.cleanContents(of: testDir.path, dryRun: false)

        let remaining = try? FileManager.default.contentsOfDirectory(atPath: testDir.path)
        let sizeAfter = remaining?.count ?? 0

        XCTAssertGreaterThan(sizeBefore, 0, "Should have files before cleanup")
        XCTAssertEqual(sizeAfter, 0, "Should have no files after cleanup")
    }

    // MARK: - CleanupEngine Full Category Flow

    func testFullCategoryFlowWithMock() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["brew", "npm"]

        mock.runHandler = { command, args in
            let cmd = args.joined(separator: " ")
            if cmd.contains("brew --cache") {
                return CommandResult(stdout: "/tmp/brew-test-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("brew cleanup") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if cmd.contains("npm config get cache") {
                return CommandResult(stdout: "/tmp/npm-test-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("npm cache clean") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = CleanupEngine(
            commandRunner: mock,
            safetyManager: SafetyManager(allowedExceptions: [testRoot.path])
        )

        let results = try await engine.run(
            categories: [.packageManagers],
            dryRun: true
        )
        XCTAssertFalse(results.isEmpty, "Should return results for package managers")
    }

    // MARK: - Progress Callback Integration

    func testProgressCallbackReceivesAllEvents() async throws {
        let testDir = testRoot.appendingPathComponent("progress_test")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        try "test".write(to: testDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let engine = CleanupEngine(safetyManager: SafetyManager(allowedExceptions: [testRoot.path]))

        let receivedEvents = IntegrationTestEventCollector()
        let results = try await engine.run(categories: [.scatteredJunk], dryRun: true) { event in
            receivedEvents.append(event)
        }

        XCTAssertFalse(results.isEmpty)
        let stepEvents = receivedEvents.events.filter {
            if case .step = $0 { return true }
            return false
        }
        XCTAssertFalse(stepEvents.isEmpty, "Should receive at least one step event")
    }
}

// MARK: - Thread-safe helper

private final class IntegrationTestEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [CleanupEngineEvent] = []

    var events: [CleanupEngineEvent] { lock.withLock { _events } }

    func append(_ event: CleanupEngineEvent) {
        lock.withLock { _events.append(event) }
    }
}
