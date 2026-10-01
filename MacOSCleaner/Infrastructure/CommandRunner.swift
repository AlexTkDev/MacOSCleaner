import Foundation
import os

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    
    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum CommandRunnerError: Error {
    case invalidExecutable
    case timeout
    case executionFailed(Int32)
}

public actor CommandRunner {
    public init() {}

    public nonisolated func run(
        command: String,
        arguments: [String] = [],
        timeout: Duration = .seconds(30)
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Use a simple lock to guard the resumed flag only.
        // stdout/stderr are read atomically after process exits — no readabilityHandler race.
        final class ResumeGuard: @unchecked Sendable {
            private let lock = NSLock()
            private var isResumed = false

            func resumeOnce(
                continuation: CheckedContinuation<CommandResult, Error>,
                result: Result<CommandResult, Error>
            ) {
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                continuation.resume(with: result)
            }
        }

        let guard_ = ResumeGuard()

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CommandResult.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        process.terminationHandler = { proc in
                            // Close write ends before reading so readDataToEndOfFile
                            // doesn't block when child processes inherited the pipe fds.
                            stdoutPipe.fileHandleForWriting.closeFile()
                            stderrPipe.fileHandleForWriting.closeFile()
                            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                            let result = CommandResult(
                                stdout: String(decoding: stdoutData, as: UTF8.self),
                                stderr: String(decoding: stderrData, as: UTF8.self),
                                exitCode: proc.terminationStatus
                            )
                            guard_.resumeOnce(continuation: continuation, result: .success(result))
                        }

                        do {
                            try process.run()
                        } catch {
                            guard_.resumeOnce(
                                continuation: continuation,
                                result: .failure(CommandRunnerError.invalidExecutable)
                            )
                        }
                    }
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    if process.isRunning {
                        process.terminate()
                    }
                    throw CommandRunnerError.timeout
                }

                guard let result = try await group.next() else {
                    throw CommandRunnerError.invalidExecutable
                }

                group.cancelAll()
                return result
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    public nonisolated func runStreaming(
        command: String,
        arguments: [String] = []
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments

            let fullCmd = ([command] + arguments).joined(separator: " ")
            continuation.yield("[debug] Running: \(fullCmd)")

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                continuation.yield("[debug] Process started (pid=\(process.processIdentifier))")
            } catch {
                continuation.yield("[debug] process.run() threw: \(error)")
                continuation.finish(throwing: error)
                return
            }

            let stdoutTask = Task {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    continuation.yield(line)
                }
            }
            
            let stderrTask = Task {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    continuation.yield("[stderr] \(line)")
                }
            }

            let waitTask = Task {
                try? await stdoutTask.value
                try? await stderrTask.value
                
                process.waitUntilExit()
                let code = process.terminationStatus
                continuation.yield("[debug] Exited with code: \(code)")
                if code == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: CommandRunnerError.executionFailed(code))
                }
            }

            continuation.onTermination = { @Sendable _ in
                stdoutTask.cancel()
                stderrTask.cancel()
                waitTask.cancel()
                if process.isRunning { process.terminate() }
            }
        }
    }
}

public enum ShellQuoting {
    /// Single-quote a string for `/bin/sh`, including embedded quotes.
    public static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}