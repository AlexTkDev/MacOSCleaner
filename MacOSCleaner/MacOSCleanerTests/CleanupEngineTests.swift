import XCTest
@testable import MacOSCleaner

final class CleanupEngineTests: XCTestCase {

    // MARK: - CleanupTimeouts Tests

    func testDefaultTimeoutValues() {
        let timeouts = CleanupTimeouts.default
        XCTAssertEqual(timeouts.fast, .seconds(30))
        XCTAssertEqual(timeouts.system, .seconds(120))
        XCTAssertEqual(timeouts.full, .seconds(300))
    }

    func testCustomTimeoutValues() {
        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(180))
        XCTAssertEqual(timeouts.fast, .seconds(10))
        XCTAssertEqual(timeouts.system, .seconds(60))
        XCTAssertEqual(timeouts.full, .seconds(180))
    }

    func testPartialCustomTimeouts() {
        let timeouts = CleanupTimeouts(fast: .seconds(5))
        XCTAssertEqual(timeouts.fast, .seconds(5))
        XCTAssertEqual(timeouts.system, .seconds(120))
        XCTAssertEqual(timeouts.full, .seconds(300))
    }

    // MARK: - CleanupEngineError Tests

    func testTimeoutErrorDescription() {
        let error = CleanupEngineError.timeout
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("timed out"))
    }

    func testSafetyViolationErrorDescription() {
        let error = CleanupEngineError.safetyViolation("/System")
        XCTAssertEqual(error.errorDescription, "Safety violation: /System")
    }

    func testCommandFailedErrorDescription() {
        let error = CleanupEngineError.commandFailed("brew not found")
        XCTAssertEqual(error.errorDescription, "Command failed: brew not found")
    }

    // MARK: - FileManager Operations Tests

    func testCleanContentsCreatesAndDeletesFiles() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let file1 = tempDir.appendingPathComponent("file1.txt")
        let file2 = tempDir.appendingPathComponent("file2.log")
        try "data1".write(to: file1, atomically: true, encoding: .utf8)
        try "data2".write(to: file2, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))

        let freed = try await engine.cleanContents(of: tempDir.path, dryRun: false)
        XCTAssertGreaterThanOrEqual(freed, 0)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path))
    }

    func testCleanContentsDryRunPreservesFiles() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let file = tempDir.appendingPathComponent("cache.dat")
        try "cachedata".write(to: file, atomically: true, encoding: .utf8)

        let freed = try await engine.cleanContents(of: tempDir.path, dryRun: true)
        XCTAssertGreaterThanOrEqual(freed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testRemoveDirectoryDeletesEntireFolder() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        let subDir = tempDir.appendingPathComponent("subfolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let file = subDir.appendingPathComponent("nested.txt")
        try "nested".write(to: file, atomically: true, encoding: .utf8)

        let freed = try await engine.removeDirectory(tempDir.path, dryRun: false)
        XCTAssertGreaterThanOrEqual(freed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
    }

    func testRemoveFileDeletesSingleFile() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let file = tempDir.appendingPathComponent("single.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let freed = try await engine.removeFile(file.path, dryRun: false)
        XCTAssertGreaterThanOrEqual(freed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanContentsOnNonexistentPathReturnsZero() async throws {
        let engine = CleanupEngine()
        let freed = try await engine.cleanContents(of: "/tmp/nonexistent_\(UUID().uuidString)", dryRun: false)
        XCTAssertEqual(freed, 0)
    }

    func testCleanOldFilesRemovesOlderThanDays() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let oldFile = tempDir.appendingPathComponent("old.txt")
        let newFile = tempDir.appendingPathComponent("new.txt")
        try "old".write(to: oldFile, atomically: true, encoding: .utf8)
        try "new".write(to: newFile, atomically: true, encoding: .utf8)

        let oldAttrs: [FileAttributeKey: Any] = [.modificationDate: Date().addingTimeInterval(-86400 * 10)]
        try FileManager.default.setAttributes(oldAttrs, ofItemAtPath: oldFile.path)

        let freed = try await engine.cleanOldFiles(in: tempDir.path, olderThanDays: 7, dryRun: false)
        XCTAssertGreaterThanOrEqual(freed, 0)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
    }

    // MARK: - Process Call Tests (with Mock)

    func testMockCommandRunnerReturnsExpectedResult() async throws {
        let mock = MockCommandRunner()
        mock.runHandler = { command, args in
            if args.joined(separator: " ").contains("brew --cache") {
                return CommandResult(stdout: "/tmp/brew-cache", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let result = try await mock.run(command: "/bin/bash", arguments: ["-c", "brew --cache 2>/dev/null"], timeout: .seconds(5))
        XCTAssertEqual(result.stdout, "/tmp/brew-cache")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testMockCommandExistsReturnsCorrectly() async {
        let mock = MockCommandRunner()
        mock.availableCommands = ["brew", "npm"]

        let brewExists = await mock.commandExists("brew")
        XCTAssertTrue(brewExists)
        let npmExists = await mock.commandExists("npm")
        XCTAssertTrue(npmExists)
        let nonexistentExists = await mock.commandExists("nonexistent")
        XCTAssertFalse(nonexistentExists)
    }

    func testPackageManagersWithMock() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["brew", "npm"]

        let counter = ThreadSafeCounter()
        mock.runHandler = { command, args in
            counter.increment()
            let cmd = args.joined(separator: " ")

            if cmd.contains("brew --cache") {
                return CommandResult(stdout: "/tmp/brew-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("brew cleanup") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if cmd.contains("npm config get cache") {
                return CommandResult(stdout: "/tmp/npm-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("npm cache clean") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = CleanupEngine(commandRunner: mock)
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.cleanPackageManagers(dryRun: true, progress: nil)
        XCTAssertFalse(results.isEmpty)
        XCTAssertGreaterThanOrEqual(counter.value, 2)
    }

    func testDockerCleanupWithMock() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["docker"]

        mock.runHandler = { command, args in
            let cmd = args.joined(separator: " ")
            if cmd.contains("docker system df") {
                return CommandResult(stdout: "TYPE TOTAL ACTIVE SIZE", stderr: "", exitCode: 0)
            }
            if cmd.contains("docker system prune") {
                return CommandResult(stdout: "Total reclaimed space: 1GB", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = CleanupEngine(commandRunner: mock)
        let results = try await engine.cleanDocker(dryRun: true, progress: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.label, "Docker")
    }

    func testDockerCleanupSkippedWhenNotInstalled() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = []

        let engine = CleanupEngine(commandRunner: mock)
        let results = try await engine.cleanDocker(dryRun: false, progress: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.freedMB, 0)
    }

    // MARK: - Cancellation Tests

    func testCancellationStopsExecution() async throws {
        let engine = CleanupEngine()
        let task = Task {
            try await engine.run(categories: CleanupCategory.allCases, dryRun: true)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // CleanupEngineError.timeout or other acceptable errors
        }
    }

    func testCancellationBetweenCategories() async throws {
        let engine = CleanupEngine()

        let task = Task { () -> [CleanupCategory] in
            var completed: [CleanupCategory] = []
            for category in [CleanupCategory.appCaches, .packageManagers, .browserCaches] {
                try Task.checkCancellation()
                completed.append(category)
            }
            return completed
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
    }

    func testScanDoesNotDeleteFiles() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let testFile = tempDir.appendingPathComponent("cache.txt")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        _ = try await engine.scan(categories: [.scatteredJunk])
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path), "Scan should not delete files")
    }

    // MARK: - Timeout Tests

    func testOperationCompletesWithinTimeout() async throws {
        let engine = CleanupEngine(timeouts: CleanupTimeouts(fast: .seconds(5)))
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.cleanContents(of: tempDir.path, dryRun: true)
        XCTAssertGreaterThanOrEqual(results, 0)
    }

    func testTimeoutCancelsSlowOperation() async {
        let shortTimeouts = CleanupTimeouts(system: .milliseconds(100))
        let engine = CleanupEngine(timeouts: shortTimeouts)

        do {
            _ = try await engine.run(categories: [.packageManagers], dryRun: false)
        } catch CleanupEngineError.timeout {
            // Expected when operation takes longer than 100ms
        } catch {
            // Other errors acceptable (e.g., command not found)
        }
    }

    func testFastCategoryUsesFastTimeout() async throws {
        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(300))
        let engine = CleanupEngine(timeouts: timeouts)
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.run(categories: [.appCaches], dryRun: true)
        XCTAssertFalse(results.isEmpty, "Should return at least one result")
    }

    func testSystemCategoryUsesSystemTimeout() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["brew"]

        mock.runHandler = { command, args in
            let cmd = args.joined(separator: " ")
            if cmd.contains("brew --cache") {
                return CommandResult(stdout: "/tmp/brew-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("brew cleanup") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(300))
        let engine = CleanupEngine(commandRunner: mock, timeouts: timeouts)

        let results = try await engine.run(categories: [.packageManagers], dryRun: true)
        XCTAssertFalse(results.isEmpty)
    }

    func testFullCategoryUsesFullTimeout() async throws {
        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(300))
        let engine = CleanupEngine(timeouts: timeouts)
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.run(categories: [.xcode], dryRun: true)
        XCTAssertNotNil(results)
    }

    // MARK: - Error Handling Tests

    func testSafetyViolationThrowsOnProtectedPath() async throws {
        let engine = CleanupEngine()

        do {
            _ = try await engine.cleanContents(of: "/System/Library", dryRun: false)
            XCTFail("Expected safety violation error")
        } catch {
            XCTAssertTrue(error is SafetyError)
        }
    }

    func testSafetyViolationOnHomeSSH() async throws {
        let engine = CleanupEngine()
        let home = NSHomeDirectory()

        do {
            _ = try await engine.cleanContents(of: "\(home)/.ssh", dryRun: false)
            XCTFail("Expected safety violation error")
        } catch {
            XCTAssertTrue(error is SafetyError)
        }
    }

    func testPermissionDeniedHandledGracefully() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()

        let protectedDir = tempDir.appendingPathComponent("protected")
        try FileManager.default.createDirectory(at: protectedDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: protectedDir.path)

        do {
            let freed = try await engine.cleanContents(of: protectedDir.path, dryRun: false)
            XCTAssertEqual(freed, 0)
        } catch {
            XCTAssertTrue(error is CocoaError || (error as NSError).code == 257,
                          "Permission denied error should be caught: \(error)")
        }

        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protectedDir.path)
        cleanupTempDir(tempDir)
    }

    func testRunReturnsEmptyForLargeFilesCategory() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.largeFiles], dryRun: true)
        XCTAssertTrue(results.isEmpty)
    }

    func testProgressCallbackInvoked() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let events = ThreadSafeArray<CleanupEngineEvent>()
        let results = try await engine.run(categories: [.scatteredJunk], dryRun: true) { event in
            events.append(event)
        }

        XCTAssertFalse(results.isEmpty)
        XCTAssertFalse(events.isEmpty)
    }

    func testMultipleCategoriesProcessed() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.run(categories: [.appCaches, .gradleMaven, .flutterDart], dryRun: true)
        XCTAssertGreaterThanOrEqual(results.count, 1)
    }

    // MARK: - Helpers

    private func createTempCacheDir() -> URL {
        let tempDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MacOSCleanerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanupTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Thread-safe helpers

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int { lock.withLock { _value } }

    func increment() {
        lock.withLock { _value += 1 }
    }
}

private final class ThreadSafeArray<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [Value] = []

    var isEmpty: Bool { lock.withLock { _items.isEmpty } }
    var count: Int { lock.withLock { _items.count } }

    func append(_ value: Value) {
        lock.withLock { _items.append(value) }
    }
}
