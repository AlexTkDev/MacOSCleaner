import Foundation
import os.log

private extension Logger {
    static let privileged = Logger(subsystem: "com.macoscleaner", category: "PrivilegedTaskRunner")
}

/// Executes a shell command with administrator privileges via NSAppleScript.
public actor PrivilegedTaskRunner {
    public enum PrivilegedError: Error {
        case appleScriptFailed(String)
        case executionFailed
        case invalidCommand
    }

    /// Escapes a shell command for the double-quoted string inside `do shell script "..."`.
    /// `$` and backticks stay literal: callers quote paths with `ShellQuoting.shellQuoted`.
    /// Newlines and NUL are rejected so a path cannot be rewritten into a different command.
    public nonisolated static func escapedForAppleScriptString(_ command: String) throws -> String {
        if command.contains("\n") || command.contains("\r") || command.contains("\0") {
            throw PrivilegedError.invalidCommand
        }
        return command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    public nonisolated static func appleScriptSource(command: String, administrator: Bool = true) throws -> String {
        let escaped = try escapedForAppleScriptString(command)
        let privileges = administrator ? " with administrator privileges" : ""
        return "do shell script \"\(escaped)\"\(privileges)"
    }

    public static func runAsAdmin(command: String) async throws -> String {
        try Task.checkCancellation()
        let scriptSource = try appleScriptSource(command: command, administrator: true)
        let runnerTask = Task.detached {
            try Task.checkCancellation()
            guard let appleScript = NSAppleScript(source: scriptSource) else {
                throw PrivilegedError.executionFailed
            }

            try Task.checkCancellation()
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)

            if let error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                Logger.privileged.error("AppleScript privileged execution failed: \(errorMessage, privacy: .public)")
                throw PrivilegedError.appleScriptFailed(errorMessage)
            }

            return result.stringValue ?? ""
        }

        return try await withTaskCancellationHandler {
            try await runnerTask.value
        } onCancel: {
            runnerTask.cancel()
        }
    }

    /// `/bin/rm -rf` as admin. Returns URLs that are still on disk.
    public static func removeAsAdmin(_ urls: [URL]) async throws -> [URL] {
        guard !urls.isEmpty else { return [] }
        let command = (["/bin/rm", "-rf"] + urls.map { ShellQuoting.shellQuoted($0.path) }).joined(separator: " ")
        _ = try await runAsAdmin(command: command)
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
