import XCTest
@testable import MacOSCleaner

final class ProcessSafetyPolicyTests: XCTestCase {

    func testPIDZeroAndOneBlocked() {
        let policy = ProcessSafetyPolicy()
        let kernelTask = RunningProcess(
            pid: 0,
            name: "kernel_task",
            path: nil,
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 0,
            bundleID: nil
        )
        if case .blocked = policy.isKillable(kernelTask) {
            // Success
        } else {
            XCTFail("PID 0 must be blocked")
        }

        let launchd = RunningProcess(
            pid: 1,
            name: "launchd",
            path: "/sbin/launchd",
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 0,
            bundleID: nil
        )
        if case .blocked = policy.isKillable(launchd) {
            // Success
        } else {
            XCTFail("PID 1 must be blocked")
        }
    }

    func testCurrentPIDBlocked() {
        let policy = ProcessSafetyPolicy()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let selfProc = RunningProcess(
            pid: currentPID,
            name: "MacOSCleaner",
            path: "/Applications/MacOSCleaner.app/Contents/MacOS/MacOSCleaner",
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 1,
            bundleID: "input.MacOSCleaner"
        )
        if case .blocked = policy.isKillable(selfProc) {
            // Success
        } else {
            XCTFail("Current PID must be blocked")
        }
    }

    func testOwnBundleIDBlocked() {
        let policy = ProcessSafetyPolicy()
        if let ownBundleID = Bundle.main.bundleIdentifier {
            let proc = RunningProcess(
                pid: 99999,
                name: "MacOSCleanerHelper",
                path: "/path/to/helper",
                user: nil,
                cpuPercent: 0,
                memoryBytes: 0,
                threadCount: 0,
                startTime: nil,
                parentPID: 1,
                bundleID: ownBundleID
            )
            if case .blocked = policy.isKillable(proc) {
                // Success
            } else {
                XCTFail("Own bundle ID must be blocked")
            }
        }
    }

    func testDefaultProtectedProcessesBlocked() {
        let policy = ProcessSafetyPolicy()
        let windowServer = RunningProcess(
            pid: 1234,
            name: "WindowServer",
            path: "/System/Library/Frameworks/CoreGraphics.framework/WindowServer",
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 1,
            bundleID: nil
        )
        if case .blocked = policy.isKillable(windowServer) {
            // Success
        } else {
            XCTFail("WindowServer must be blocked")
        }
    }

    func testUserBlacklistBlocks() {
        var policy = ProcessSafetyPolicy()
        policy.addToBlacklist("MyCustomApp")

        let proc = RunningProcess(
            pid: 5678,
            name: "MyCustomApp",
            path: "/Applications/MyCustomApp.app/Contents/MacOS/MyCustomApp",
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 1,
            bundleID: "com.example.mycustomapp"
        )
        if case .blocked = policy.isKillable(proc) {
            // Success
        } else {
            XCTFail("User blacklist must block process from being killed")
        }
    }

    func testUserWhitelistAllows() {
        var policy = ProcessSafetyPolicy()
        policy.addToWhitelist("Dock") // Override default protection or add allowed app

        // Normal app in whitelist
        policy.addToWhitelist("UnknownTool")
        let proc = RunningProcess(
            pid: 4321,
            name: "UnknownTool",
            path: nil, // Even without path
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 1,
            bundleID: "com.example.unknowntool"
        )
        if case .allowed = policy.isKillable(proc) {
            // Success
        } else {
            XCTFail("User whitelist must allow process without confirmation")
        }
    }

    func testProcessWithoutPathNeedsConfirmation() {
        let policy = ProcessSafetyPolicy()
        let proc = RunningProcess(
            pid: 8888,
            name: "MysteryDaemon",
            path: nil,
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 1,
            bundleID: nil
        )
        if case .needsConfirmation = policy.isKillable(proc) {
            // Success
        } else {
            XCTFail("Process without path must return .needsConfirmation")
        }
    }

    func testNeedsConfirmationDoesNotThrowInProcessManager() async throws {
        // A process with path: nil returns .needsConfirmation.
        // ProcessManager.terminate must only throw if .blocked, but not if .needsConfirmation.
        let commandRunner = CommandRunner()
        let manager = ProcessManager(commandRunner: commandRunner)

        let proc = RunningProcess(
            pid: 999999, // non-existent PID, kill will fail with exitCode != 0 (killFailed), NOT operationBlocked
            name: "MysteryProcess",
            path: nil,
            user: nil,
            cpuPercent: 0,
            memoryBytes: 0,
            threadCount: 0,
            startTime: nil,
            parentPID: 1,
            bundleID: nil
        )

        do {
            try await manager.terminate(proc)
        } catch let error as ProcessManagerError {
            switch error {
            case .operationBlocked:
                XCTFail("Process with .needsConfirmation must not throw operationBlocked")
            case .killFailed:
                // Expected because PID 999999 doesn't exist, /bin/kill returns 1
                break
            default:
                break
            }
        }
    }
}
