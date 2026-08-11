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

    public func run(
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

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.invalidExecutable
        }

        let isTimedOut = OSAllocatedUnfairLock(initialState: false)

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CommandResult.self) { group in
                group.addTask {
                    async let stdoutData = Task.detached {
                        stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    }.value

                    async let stderrData = Task.detached {
                        stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    }.value

                    let exitCode = await Task.detached {
                        process.waitUntilExit()
                        return process.terminationStatus
                    }.value

                    let out = try await stdoutData
                    let err = try await stderrData

                    if isTimedOut.withLock({ $0 }) {
                        throw CommandRunnerError.timeout
                    }

                    try Task.checkCancellation()

                    return CommandResult(
                        stdout: String(decoding: out, as: UTF8.self),
                        stderr: String(decoding: err, as: UTF8.self),
                        exitCode: exitCode
                    )
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    isTimedOut.withLock { $0 = true }
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