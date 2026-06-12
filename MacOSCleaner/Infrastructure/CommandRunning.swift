import Foundation

/// Protocol abstracting command execution for testability.
public protocol CommandRunning: Sendable {
    func run(command: String, arguments: [String], timeout: Duration) async throws -> CommandResult
    func runWithRetry(command: String, arguments: [String], timeout: Duration, retryPolicy: RetryPolicy) async throws -> CommandResult
    func commandExists(_ command: String) async -> Bool
}

extension CommandRunning {
    public func run(command: String, arguments: [String]) async throws -> CommandResult {
        try await run(command: command, arguments: arguments, timeout: .seconds(30))
    }

    public func run(command: String, arguments: [String], timeout: Duration) async throws -> CommandResult {
        try await run(command: command, arguments: arguments, timeout: timeout)
    }

    public func runWithRetry(command: String, arguments: [String]) async throws -> CommandResult {
        try await runWithRetry(command: command, arguments: arguments, timeout: .seconds(30), retryPolicy: .default)
    }
}

extension CommandRunner: CommandRunning {
    public func commandExists(_ command: String) async -> Bool {
        let result = try? await run(command: "/bin/bash", arguments: ["-c", "command -v \(command) 2>/dev/null"])
        return result?.exitCode == 0
    }

    public func runWithRetry(
        command: String,
        arguments: [String],
        timeout: Duration = .seconds(30),
        retryPolicy: RetryPolicy = .default
    ) async throws -> CommandResult {
        try await withRetry(policy: retryPolicy) {
            try await self.run(command: command, arguments: arguments, timeout: timeout)
        }
    }
}
