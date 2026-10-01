import AppKit
import Foundation

/// Graceful quit, then force-terminate anything still running after the deadline.
/// Cancellation during the graceful wait returns without force-terminate.
@MainActor
public enum AppQuitter {
    public struct Handle: @unchecked Sendable {
        public let name: String
        let terminate: () -> Bool
        let forceTerminate: () -> Bool
        let isTerminated: () -> Bool

        public init(
            name: String,
            terminate: @escaping () -> Bool,
            forceTerminate: @escaping () -> Bool,
            isTerminated: @escaping () -> Bool
        ) {
            self.name = name
            self.terminate = terminate
            self.forceTerminate = forceTerminate
            self.isTerminated = isTerminated
        }

        public init(application: NSRunningApplication) {
            self.init(
                name: application.localizedName ?? "Unknown",
                terminate: { application.terminate() },
                forceTerminate: { application.forceTerminate() },
                isTerminated: { application.isTerminated }
            )
        }
    }

    public struct Outcome: Sendable {
        public let forced: [String]
        public let stillRunning: [String]
    }

    public static func quit(
        _ apps: [Handle],
        gracefulTimeout: Duration = .seconds(3),
        forceCheckTimeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(100)
    ) async -> Outcome {
        let targets = apps.filter { !$0.isTerminated() }
        guard !targets.isEmpty else {
            return Outcome(forced: [], stillRunning: [])
        }

        for app in targets {
            _ = app.terminate()
        }

        if await waitUntilTerminated(targets, timeout: gracefulTimeout, pollInterval: pollInterval) {
            return Outcome(forced: [], stillRunning: [])
        }
        if Task.isCancelled {
            return Outcome(forced: [], stillRunning: targets.filter { !$0.isTerminated() }.map(\.name))
        }

        var forced: [String] = []
        for app in targets where !app.isTerminated() {
            _ = app.forceTerminate()
            forced.append(app.name)
        }

        _ = await waitUntilTerminated(targets, timeout: forceCheckTimeout, pollInterval: pollInterval)
        let stillRunning = targets.filter { !$0.isTerminated() }.map(\.name)
        return Outcome(forced: forced, stillRunning: stillRunning)
    }

    /// Regular, non-Apple, policy-allowed apps. Shared by cleanup so the policy filter lives in one place.
    public static func cleanupTargets(policy: ProcessSafetyPolicy = ProcessSafetyPolicy()) -> [Handle] {
        // Unit tests call executeCleanup against an isolated filesystem. Quitting live apps there
        // would kill the developer's session.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return []
        }
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.activationPolicy == .regular else { return nil }
            let bundleID = application.bundleIdentifier ?? ""
            guard bundleID != Bundle.main.bundleIdentifier, !bundleID.hasPrefix("com.apple.") else {
                return nil
            }
            let process = RunningProcess(application: application)
            guard case .allowed = policy.isKillable(process) else { return nil }
            return Handle(application: application)
        }
    }

    private static func waitUntilTerminated(
        _ targets: [Handle],
        timeout: Duration,
        pollInterval: Duration
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return false }
            if targets.allSatisfy({ $0.isTerminated() }) { return true }
            do {
                try await Task.sleep(for: pollInterval)
            } catch is CancellationError {
                return false
            } catch {
                return false
            }
        }
        return targets.allSatisfy { $0.isTerminated() }
    }
}

extension RunningProcess {
    @MainActor
    init(application: NSRunningApplication) {
        self.init(
            pid: application.processIdentifier,
            name: application.localizedName ?? "Unknown",
            path: application.bundleURL?.path,
            bundleID: application.bundleIdentifier
        )
    }
}
