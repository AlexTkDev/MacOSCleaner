import Foundation
import os

public actor ProcessManager {
    private let commandRunner: CommandRunner
    private var safetyPolicy: ProcessSafetyPolicy
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "ProcessManager"
    )

    public init(
        commandRunner: CommandRunner = CommandRunner(),
        safetyPolicy: ProcessSafetyPolicy = ProcessSafetyPolicy()
    ) {
        self.commandRunner = commandRunner
        self.safetyPolicy = safetyPolicy
    }

    public func listProcesses() async throws -> [RunningProcess] {
        let result = try await commandRunner.run(
            command: "/bin/ps",
            arguments: ["-axo", "pid,comm,path"],
            timeout: .seconds(10)
        )

        guard result.exitCode == 0 else {
            logger.error("ps failed with exit code \(result.exitCode): \(result.stderr)")
            throw ProcessManagerError.psFailed(result.stderr)
        }

        return parsePsOutput(result.stdout)
    }

    public func searchProcesses(named query: String) async throws -> [RunningProcess] {
        let all = try await listProcesses()
        let lowered = query.lowercased()
        return all.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.path?.lowercased().contains(lowered) == true
        }
    }

    public func terminate(_ process: RunningProcess) async throws {
        let permission = safetyPolicy.isKillable(process)
        guard case .allowed = permission else {
            throw ProcessManagerError.operationBlocked(
                processName: process.name,
                reason: permission.blockReason ?? "Unknown"
            )
        }

        logger.info("Terminating \(process.name) (PID \(process.pid)) with SIGTERM")
        let result = try await commandRunner.run(
            command: "/bin/kill",
            arguments: ["-15", "\(process.pid)"],
            timeout: .seconds(5)
        )

        if result.exitCode != 0 {
            throw ProcessManagerError.killFailed(
                processName: process.name,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    public func forceKill(_ process: RunningProcess) async throws {
        let permission = safetyPolicy.isKillable(process)
        guard case .allowed = permission else {
            throw ProcessManagerError.operationBlocked(
                processName: process.name,
                reason: permission.blockReason ?? "Unknown"
            )
        }

        logger.warning("Force killing \(process.name) (PID \(process.pid)) with SIGKILL")
        let result = try await commandRunner.run(
            command: "/bin/kill",
            arguments: ["-9", "\(process.pid)"],
            timeout: .seconds(5)
        )

        if result.exitCode != 0 {
            throw ProcessManagerError.killFailed(
                processName: process.name,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    public func gracefulShutdown(
        _ process: RunningProcess,
        timeout: TimeInterval = 5.0
    ) async throws {
        let permission = safetyPolicy.isKillable(process)
        guard case .allowed = permission else {
            throw ProcessManagerError.operationBlocked(
                processName: process.name,
                reason: permission.blockReason ?? "Unknown"
            )
        }

        logger.info("Graceful shutdown of \(process.name) (PID \(process.pid))")

        try await terminate(process)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await !isProcessAlive(process.pid) {
                logger.info("\(process.name) terminated gracefully")
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        logger.warning("\(process.name) did not exit, force killing")
        try await forceKill(process)
    }

    public func isProcessAlive(_ pid: pid_t) async throws -> Bool {
        let result = try await commandRunner.run(
            command: "/bin/kill",
            arguments: ["-0", "\(pid)"],
            timeout: .seconds(3)
        )
        return result.exitCode == 0
    }

    public func checkPermission(_ process: RunningProcess) -> KillPermission {
        safetyPolicy.isKillable(process)
    }

    public func addToBlacklist(_ name: String) {
        safetyPolicy.addToBlacklist(name)
    }

    public func removeFromBlacklist(_ name: String) {
        safetyPolicy.removeFromBlacklist(name)
    }

    public func addToWhitelist(_ name: String) {
        safetyPolicy.addToWhitelist(name)
    }

    public func removeFromWhitelist(_ name: String) {
        safetyPolicy.removeFromWhitelist(name)
    }

    public func getBlacklist() -> Set<String> {
        safetyPolicy.blacklist
    }

    public func getWhitelist() -> Set<String> {
        safetyPolicy.whitelist
    }

    public func getProtected() -> Set<String> {
        safetyPolicy.protected
    }

    private func parsePsOutput(_ output: String) -> [RunningProcess] {
        var processes: [RunningProcess] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard parts.count >= 2,
                  let pid = pid_t(parts[0]) else { continue }

            let name = parts[1]
            let path = parts.count >= 3 ? parts[2] : nil

            processes.append(
                RunningProcess(pid: pid, name: name, path: path)
            )
        }

        return processes
    }
}

public enum ProcessManagerError: Error, LocalizedError {
    case psFailed(String)
    case operationBlocked(processName: String, reason: String)
    case killFailed(processName: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .psFailed(let stderr):
            return "Failed to list processes: \(stderr)"
        case .operationBlocked(let name, let reason):
            return "Cannot terminate \(name): \(reason)"
        case .killFailed(let name, let code, let stderr):
            return "Failed to kill \(name) (exit \(code)): \(stderr)"
        }
    }
}

private extension KillPermission {
    var blockReason: String? {
        switch self {
        case .blocked(let reason): return reason
        default: return nil
        }
    }
}
