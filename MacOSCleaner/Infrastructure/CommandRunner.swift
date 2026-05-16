import Foundation

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

        return try await withTaskCancellationHandler {
            try process.run()

            return try await withThrowingTaskGroup(of: CommandResult.self) { group in
                
                group.addTask {
                    async let stdoutBytes = stdoutPipe.fileHandleForReading.readToEndAsync()
                    async let stderrBytes = stderrPipe.fileHandleForReading.readToEndAsync()

                    let stdoutData = try await stdoutBytes ?? Data()
                    let stderrData = try await stderrBytes ?? Data()

                    let exitCode = await withCheckedContinuation { continuation in
                        if !process.isRunning {
                            continuation.resume(returning: process.terminationStatus)
                        } else {
                            process.terminationHandler = { p in
                                continuation.resume(returning: p.terminationStatus)
                            }
                        }
                    }

                    return CommandResult(
                        stdout: String(decoding: stdoutData, as: UTF8.self),
                        stderr: String(decoding: stderrData, as: UTF8.self),
                        exitCode: exitCode
                    )
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

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: CommandRunnerError.executionFailed(p.terminationStatus))
                }
            }

            do {
                try process.run()
                
                Task.detached {
                    let reader = pipe.fileHandleForReading
                    for try await line in reader.bytes.lines {
                        continuation.yield(line)
                    }
                }
            } catch {
                continuation.finish(throwing: error)
            }
            
            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}

extension FileHandle {
    func readToEndAsync() async throws -> Data? {
        try await Task.detached {
            try self.readToEnd()
        }.value
    }
}