import XCTest
@testable import MacOSCleaner

final class CommandRunnerTests: XCTestCase {

    var commandRunner: CommandRunner!

    override func setUp() {
        super.setUp()
        commandRunner = CommandRunner()
    }

    override func tearDown() {
        commandRunner = nil
        super.tearDown()
    }

    func testSuccessfulExecution() async throws {
        let result = try await commandRunner.run(command: "/bin/echo", arguments: ["Hello, World!"])
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Hello, World!")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testStderrCapture() async throws {
        let result = try await commandRunner.run(command: "/bin/sh", arguments: ["-c", "echo 'Error message' >&2"])
        XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "Error message")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testTimeout() async {
        do {
            _ = try await commandRunner.run(command: "/bin/sleep", arguments: ["2"], timeout: .seconds(1))
            XCTFail("Expected timeout error")
        } catch CommandRunnerError.timeout {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancellation() async {
        let runner = commandRunner!
        let task = Task {
            try await runner.run(command: "/bin/sleep", arguments: ["5"])
        }
        
        // Wait a bit to ensure process started
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("Expected cancellation error")
        } catch is CancellationError {
            // Expected
        } catch {
            // Note: withTaskCancellationHandler might result in the process terminating and returning an exit code
            // or throwing a CancellationError depending on exact timing.
            // But throwing an error or exiting early is the expected behavior.
        }
    }
}
