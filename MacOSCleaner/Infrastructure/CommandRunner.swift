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
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Parent still holds pipe write ends until we close them. Drain on
        // dedicated threads so a fast-exiting child cannot drop stderr (CI flake:
        // terminationHandler nilling readabilityHandler races availableData).
        let stdoutTask = Task.detached(priority: .utility) {
            CommandRunner.readPipeToEnd(stdoutHandle)
        }
        let stderrTask = Task.detached(priority: .utility) {
            CommandRunner.readPipeToEnd(stderrHandle)
        }

        let stdoutWrite = stdoutPipe.fileHandleForWriting
        let stderrWrite = stderrPipe.fileHandleForWriting

        let exitCode: Int32
        do {
            exitCode = try await withTaskCancellationHandler {
                try await CommandRunner.waitForExit(process, timeout: timeout)
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
                try? stdoutWrite.close()
                try? stderrWrite.close()
            }
            try? stdoutWrite.close()
            try? stderrWrite.close()
        } catch {
            if process.isRunning {
                process.terminate()
            }
            try? stdoutWrite.close()
            try? stderrWrite.close()
            _ = await stdoutTask.value
            _ = await stderrTask.value
            throw error
        }

        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        return CommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: exitCode
        )
    }

    /// Blocks until EOF. Empty `availableData` is EOF on a pipe.
    private nonisolated static func readPipeToEnd(_ handle: FileHandle) -> Data {
        var data = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    private nonisolated static func waitForExit(_ process: Process, timeout: Duration) async throws -> Int32 {
        final class ResumeOnce: @unchecked Sendable {
            private let lock = NSLock()
            private var isResumed = false

            func resume(
                _ continuation: CheckedContinuation<Int32, Error>,
                _ result: Result<Int32, Error>
            ) {
                lock.lock()
                defer { lock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                continuation.resume(with: result)
            }
        }

        let resume = ResumeOnce()
        return try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { proc in
                        resume.resume(continuation, .success(proc.terminationStatus))
                    }
                    do {
                        try process.run()
                    } catch {
                        resume.resume(continuation, .failure(CommandRunnerError.invalidExecutable))
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

            guard let code = try await group.next() else {
                throw CommandRunnerError.invalidExecutable
            }
            group.cancelAll()
            return code
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