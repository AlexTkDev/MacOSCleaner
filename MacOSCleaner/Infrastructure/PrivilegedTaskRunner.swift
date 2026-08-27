import Foundation
import os.log

private extension Logger {
    static let privileged = Logger(subsystem: "com.macoscleaner", category: "PrivilegedTaskRunner")
}

/// A utility to execute shell commands with administrator privileges via NSAppleScript.
public actor PrivilegedTaskRunner {
    public enum PrivilegedError: Error {
        case appleScriptFailed(String)
        case executionFailed
    }
    
    /// Executes a shell command with administrator privileges.
    /// - Parameter command: The command to execute (e.g. `tmutil thinlocalsnapshots / 10000000000 4`)
    /// - Returns: The stdout output of the command.
    /// - Throws: An error if execution fails or user cancels the password prompt.
    public static func runAsAdmin(command: String) async throws -> String {
        return try await Task.detached {
            // Escape double quotes and backslashes in the command
            let escapedCommand = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            
            let scriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges"
            guard let appleScript = NSAppleScript(source: scriptSource) else {
                throw PrivilegedError.executionFailed
            }
            
            var error: NSDictionary? = nil
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                Logger.privileged.error("AppleScript privileged execution failed: \(errorMessage, privacy: .public)")
                throw PrivilegedError.appleScriptFailed(errorMessage)
            }
            
            return result.stringValue ?? ""
        }.value
    }
}
