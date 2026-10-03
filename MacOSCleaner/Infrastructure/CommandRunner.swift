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
        // stdout/stderr are read via readabilityHandler (prevents pipe-buffer deadlock on large
        // outputs) and drained atomically in terminationHandler after write ends are closed.
        final class ProcessState: @unchecked Sendable {
            private let lock = NSLock()
            private var isResumed = false
            private var timedOut = false
            private var stdoutData = Data()
            private var stderrData = Data()

            func appendStdout(_ data: Data) {
                lock.lock()
                stdoutData.append(data)
                lock.unlock()
            }

            func appendStderr(_ data: Data) {
                lock.lock()
                stderrData.append(data)
                lock.unlock()
            }

            func markTimedOut() {
                lock.lock()
                timedOut = true
                lock.unlock()
            }

            var didTimeOut: Bool {
                lock.lock()
                defer { lock.unlock() }
                return timedOut
            }

            func finish(process: Process, remainingOut: Data, remainingErr: Data) -> CommandResult {
                lock.lock()
                defer { lock.unlock() }
                if !remainingOut.isEmpty { stdoutData.append(remainingOut) }
                if !remainingErr.isEmpty { stderrData.append(remainingErr) }
                return CommandResult(
                    stdout: String(decoding: stdoutData, as: UTF8.self),
                    stderr: String(decoding: stderrData, as: UTF8.self),
                    exitCode: process.terminationStatus
                )
            }

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

        let state = ProcessState()

        // Drain pipe buffers continuously — required to prevent deadlock when
        // the process produces more output than the pipe buffer (~64 KB on macOS).
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { state.appendStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { state.appendStderr(data) }
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CommandResult.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        process.terminationHandler = { proc in
                            // Stop handler-based draining.
                            stdoutPipe.fileHandleForReading.readabilityHandler = nil
                            stderrPipe.fileHandleForReading.readabilityHandler = nil
                            // Close parent's write-end copies so readDataToEndOfFile
                            // gets EOF immediately (not blocked by dangling write fds).
                            stdoutPipe.fileHandleForWriting.closeFile()
                            stderrPipe.fileHandleForWriting.closeFile()
                            // Drain any bytes that arrived between the last handler
                            // invocation and the terminationHandler.
                            let remOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                            let remErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                            let result = state.finish(process: proc, remainingOut: remOut, remainingErr: remErr)
                            state.resumeOnce(continuation: continuation, result: .success(result))
                        }

                        do {
                            try process.run()
                        } catch {
                            stdoutPipe.fileHandleForReading.readabilityHandler = nil
                            stderrPipe.fileHandleForReading.readabilityHandler = nil
                            state.resumeOnce(
                                continuation: continuation,
                                result: .failure(CommandRunnerError.invalidExecutable)
                            )
                        }
                    }
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    // Flag before terminate: termination handler may win the race
                    // against this task's throw and report a SIGTERM exit as success.
                    state.markTimedOut()
                    if process.isRunning {
                        process.terminate()
                    }
                    throw CommandRunnerError.timeout
                }

                guard let result = try await group.next() else {
                    throw CommandRunnerError.invalidExecutable
                }

                group.cancelAll()
                if state.didTimeOut { throw CommandRunnerError.timeout }
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