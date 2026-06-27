import Foundation
@testable import MacOSCleaner

/// Mock CommandRunner for unit testing CleanupEngine.
final class MockCommandRunner: CommandRunning, @unchecked Sendable {
    var commandExistsResult: (String) -> Bool = { _ in false }
    var runHandler: ((String, [String]) async throws -> CommandResult)?
    var runDelay: Duration = .milliseconds(10)
    var availableCommands: Set<String> = []

    func run(command: String, arguments: [String], timeout: Duration = .seconds(30)) async throws -> CommandResult {
        if let handler = runHandler {
            return try await handler(command, arguments)
        }

        let key = arguments.joined(separator: " ")
        if key.contains("command -v") {
            let cmd = key.replacingOccurrences(of: "command -v ", with: "")
                .replacingOccurrences(of: " 2>/dev/null", with: "")
            let exists = availableCommands.contains(cmd) || commandExistsResult(cmd)
            return CommandResult(
                stdout: exists ? "/usr/bin/\(cmd)" : "",
                stderr: "",
                exitCode: exists ? 0 : 1
            )
        }

        if runDelay > .milliseconds(0) {
            try await Task.sleep(for: runDelay)
        }

        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }

    func runWithRetry(command: String, arguments: [String], timeout: Duration = .seconds(30), retryPolicy: RetryPolicy = .default) async throws -> CommandResult {
        try await withRetry(policy: retryPolicy) {
            try await self.run(command: command, arguments: arguments, timeout: timeout)
        }
    }

    func commandExists(_ command: String) async -> Bool {
        availableCommands.contains(command) || commandExistsResult(command)
    }

    // Forensics engine mock helpers
    func mockCodesignTeamID(for url: URL, teamID: String) {
        runHandler = { cmd, args in
            if cmd == "/usr/bin/codesign" {
                if args.contains("-dv") {
                    if teamID.isEmpty {
                        return CommandResult(stdout: "", stderr: "code object is not signed at all", exitCode: 1)
                    }
                    return CommandResult(
                        stdout: "",
                        stderr: """
                        Executable=\(url.path)
                        Format=bundle with Mach-O thin (x86_64)
                        CodeDirectory v=20500 size=12345 flags=0x1000(runtime) hashes=123
                        TeamIdentifier=\(teamID)
                        """,
                        exitCode: 0
                    )
                }
            }
            throw CommandRunnerError.executionFailed(1)
        }
    }

    func mockMdfind(query: String, results: [String]) {
        let original = runHandler
        runHandler = { cmd, args in
            if cmd == "/usr/bin/mdfind", args.contains(query) {
                return CommandResult(stdout: results.joined(separator: "\n"), stderr: "", exitCode: 0)
            }
            if let handler = original {
                return try await handler(cmd, args)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
    }

    func mockPkgutil(bundleID: String, files: [String]) {
        let original = runHandler
        runHandler = { cmd, args in
            if cmd == "/usr/sbin/pkgutil", args.contains("--files"), args.contains(bundleID) {
                return CommandResult(stdout: files.joined(separator: "\n"), stderr: "", exitCode: 0)
            }
            if let handler = original {
                return try await handler(cmd, args)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
    }
}
