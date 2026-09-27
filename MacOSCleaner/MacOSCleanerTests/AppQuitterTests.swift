import XCTest
@testable import MacOSCleaner

@MainActor
final class AppQuitterTests: XCTestCase {
    private final class FakeApp {
        var terminated = false
        var terminateCount = 0
        var forceCount = 0
        var closesOnTerminate = true

        func handle(name: String = "Fake") -> AppQuitter.Handle {
            AppQuitter.Handle(
                name: name,
                terminate: {
                    self.terminateCount += 1
                    if self.closesOnTerminate { self.terminated = true }
                    return true
                },
                forceTerminate: {
                    self.forceCount += 1
                    self.terminated = true
                    return true
                },
                isTerminated: { self.terminated }
            )
        }
    }

    func testGracefulQuitDoesNotForce() async {
        let app = FakeApp()
        let outcome = await AppQuitter.quit(
            [app.handle()],
            gracefulTimeout: .milliseconds(200),
            pollInterval: .milliseconds(20)
        )
        XCTAssertEqual(app.terminateCount, 1)
        XCTAssertEqual(app.forceCount, 0)
        XCTAssertTrue(outcome.forced.isEmpty)
        XCTAssertTrue(outcome.stillRunning.isEmpty)
    }

    func testForceAfterGracefulTimeout() async {
        let app = FakeApp()
        app.closesOnTerminate = false
        let outcome = await AppQuitter.quit(
            [app.handle(name: "Stuck")],
            gracefulTimeout: .milliseconds(40),
            forceCheckTimeout: .milliseconds(40),
            pollInterval: .milliseconds(10)
        )
        XCTAssertEqual(app.terminateCount, 1)
        XCTAssertEqual(app.forceCount, 1)
        XCTAssertEqual(outcome.forced, ["Stuck"])
        XCTAssertTrue(outcome.stillRunning.isEmpty)
    }

    func testCancelDuringGracefulWaitSkipsForce() async {
        let app = FakeApp()
        app.closesOnTerminate = false
        let task = Task { @MainActor in
            await AppQuitter.quit(
                [app.handle()],
                gracefulTimeout: .seconds(30),
                pollInterval: .milliseconds(20)
            )
        }
        try? await Task.sleep(for: .milliseconds(40))
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(app.forceCount, 0)
        XCTAssertEqual(app.terminateCount, 1)
        XCTAssertEqual(outcome.stillRunning, ["Fake"])
    }
}
