import Foundation
import os

public actor ProcessManager {
    private let commandRunner: CommandRunner
    private let processInfoProvider: ProcessInfoProvider
    private var safetyPolicy: ProcessSafetyPolicy
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "ProcessManager"
    )

    public init(
        commandRunner: CommandRunner = CommandRunner(),
        processInfoProvider: ProcessInfoProvider = ProcessInfoProvider(),
        safetyPolicy: ProcessSafetyPolicy = ProcessSafetyPolicy()
    ) {
        self.commandRunner = commandRunner
        self.processInfoProvider = processInfoProvider
        self.safetyPolicy = safetyPolicy
    }

    public func listProcesses() async throws -> [RunningProcess] {
        try await processInfoProvider.listAllProcesses()
    }

    public func terminate(_ process: RunningProcess) async throws {
        let permission = safetyPolicy.isKillable(process)
        if case .blocked(let reason) = permission {
            throw ProcessManagerError.operationBlocked(
                processName: process.name,
                reason: reason
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
        if case .blocked(let reason) = permission {
            throw ProcessManagerError.operationBlocked(
                processName: process.name,
                reason: reason
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

    public func checkPermission(_ process: RunningProcess) -> KillPermission {
        safetyPolicy.isKillable(process)
    }

    public func checkPermissions(_ processes: [RunningProcess]) -> [pid_t: KillPermission] {
        var result: [pid_t: KillPermission] = [:]
        result.reserveCapacity(processes.count)
        for proc in processes {
            result[proc.pid] = safetyPolicy.isKillable(proc)
        }
        return result
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
}

public enum ProcessManagerError: Error, LocalizedError {
    case operationBlocked(processName: String, reason: String)
    case killFailed(processName: String, exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .operationBlocked(let name, let reason):
            return String(format: "error_operation_blocked_format".localized, name, reason)
        case .killFailed(let name, let code, let stderr):
            return String(format: "error_kill_failed_format".localized, name, code, stderr)
        }
    }
}
