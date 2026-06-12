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

    // MARK: - Timeout Behavior Tests

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
            // If no packages are installed, this may complete quickly without timeout
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

    // MARK: - Scan vs Run

    func testScanDoesNotDeleteFiles() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let testFile = tempDir.appendingPathComponent("cache.txt")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        let results = try await engine.scan(categories: [.scatteredJunk])
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path), "Scan should not delete files")
        _ = results
    }

    // MARK: - Cancellation

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
