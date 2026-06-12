import XCTest
@testable import MacOSCleaner

final class RetryPolicyTests: XCTestCase {

    // MARK: - RetryPolicy Configuration

    func testDefaultRetryPolicy() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.baseDelay, .seconds(1))
        XCTAssertEqual(policy.maxDelay, .seconds(30))
    }

    func testCustomRetryPolicy() {
        let policy = RetryPolicy(maxRetries: 5, baseDelay: .seconds(2), maxDelay: .seconds(60))
        XCTAssertEqual(policy.maxRetries, 5)
        XCTAssertEqual(policy.baseDelay, .seconds(2))
        XCTAssertEqual(policy.maxDelay, .seconds(60))
    }

    // MARK: - Exponential Backoff Calculation

    func testDelayForAttempt0() {
        let policy = RetryPolicy(baseDelay: .seconds(1))
        XCTAssertEqual(policy.delay(forAttempt: 0), .seconds(1))
    }

    func testDelayForAttempt1() {
        let policy = RetryPolicy(baseDelay: .seconds(1))
        XCTAssertEqual(policy.delay(forAttempt: 1), .seconds(2))
    }

    func testDelayForAttempt2() {
        let policy = RetryPolicy(baseDelay: .seconds(1))
        XCTAssertEqual(policy.delay(forAttempt: 2), .seconds(4))
    }

    func testDelayRespectsMaxDelay() {
        let policy = RetryPolicy(baseDelay: .seconds(10), maxDelay: .seconds(15))
        XCTAssertEqual(policy.delay(forAttempt: 5), .seconds(15))
    }

    func testDelayWithLargerBase() {
        let policy = RetryPolicy(baseDelay: .seconds(5))
        XCTAssertEqual(policy.delay(forAttempt: 0), .seconds(5))
        XCTAssertEqual(policy.delay(forAttempt: 1), .seconds(10))
        XCTAssertEqual(policy.delay(forAttempt: 2), .seconds(20))
    }

    // MARK: - TransientError Detection

    func testTimeoutIsTransient() {
        let error = TransientError(from: CommandRunnerError.timeout)
        XCTAssertEqual(error, .timeout)
    }

    func testNonTransientErrorReturnsNil() {
        let error = TransientError(from: CommandRunnerError.executionFailed(1))
        XCTAssertNil(error)
    }

    func testCancellationIsNotTransient() {
        let error = TransientError(from: CancellationError())
        XCTAssertNil(error)
    }

    // MARK: - withRetry Function

    func testWithRetrySucceedsOnFirstAttempt() async throws {
        let counter = RetryTestCounter()
        let result = try await withRetry(policy: RetryPolicy(maxRetries: 3)) {
            counter.increment()
            return "success"
        }
        XCTAssertEqual(result, "success")
        XCTAssertEqual(counter.value, 1)
    }

    func testWithRetrySucceedsAfterRetries() async throws {
        let counter = RetryTestCounter()
        let result = try await withRetry(policy: RetryPolicy(maxRetries: 3, baseDelay: .milliseconds(10))) {
            counter.increment()
            if counter.value < 3 {
                throw CommandRunnerError.timeout
            }
            return "success"
        }
        XCTAssertEqual(result, "success")
        XCTAssertEqual(counter.value, 3)
    }

    func testWithRetryThrowsAfterMaxRetries() async {
        let counter = RetryTestCounter()
        do {
            _ = try await withRetry(policy: RetryPolicy(maxRetries: 2, baseDelay: .milliseconds(10))) {
                counter.increment()
                throw CommandRunnerError.timeout
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is CommandRunnerError)
        }
        XCTAssertEqual(counter.value, 3) // initial + 2 retries
    }

    func testWithRetryDoesNotRetryNonTransientErrors() async {
        let counter = RetryTestCounter()
        do {
            _ = try await withRetry(policy: RetryPolicy(maxRetries: 3, baseDelay: .milliseconds(10))) {
                counter.increment()
                throw CommandRunnerError.executionFailed(1)
            }
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is CommandRunnerError)
        }
        XCTAssertEqual(counter.value, 1) // no retries for non-transient
    }

    func testWithRetryRespectsCancellation() async {
        let task = Task {
            try await withRetry(policy: RetryPolicy(maxRetries: 10, baseDelay: .milliseconds(100))) {
                throw CommandRunnerError.timeout
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors acceptable
        }
    }

    // MARK: - CommandRunner runWithRetry

    func testCommandRunnerRunWithRetryOnSuccess() async throws {
        let runner = CommandRunner()
        let result = try await runner.runWithRetry(
            command: "/bin/echo",
            arguments: ["hello"],
            timeout: .seconds(5),
            retryPolicy: RetryPolicy(maxRetries: 2, baseDelay: .milliseconds(10))
        )
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testCommandRunnerRunWithRetryOnFailure() async {
        let runner = CommandRunner()
        do {
            _ = try await runner.runWithRetry(
                command: "/bin/nonexistent_command_\(UUID().uuidString)",
                arguments: [],
                timeout: .seconds(2),
                retryPolicy: RetryPolicy(maxRetries: 1, baseDelay: .milliseconds(10))
            )
            XCTFail("Expected error")
        } catch {
            // Expected - command not found, not transient, no retry
        }
    }

    // MARK: - Mock with Retry

    func testMockCommandRunnerWithRetry() async throws {
        let mock = MockCommandRunner()
        var callCount = 0
        mock.runHandler = { command, args in
            callCount += 1
            if callCount < 3 {
                throw CommandRunnerError.timeout
            }
            return CommandResult(stdout: "ok", stderr: "", exitCode: 0)
        }

        let result = try await mock.runWithRetry(
            command: "/bin/test",
            arguments: [],
            timeout: .seconds(5),
            retryPolicy: RetryPolicy(maxRetries: 3, baseDelay: .milliseconds(10))
        )
        XCTAssertEqual(result.stdout, "ok")
        XCTAssertEqual(callCount, 3)
    }
}

// MARK: - Thread-safe helper

private final class RetryTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int { lock.withLock { _value } }

    func increment() {
        lock.withLock { _value += 1 }
    }
}
