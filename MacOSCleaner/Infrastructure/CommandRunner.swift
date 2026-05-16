import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum CommandRunnerError: Error {
    case invalidExecutable
    case timeout
}

actor CommandRunner {

    func run(
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
}

extension FileHandle {
    func readToEndAsync() async throws -> Data? {
        try await Task.detached {
            try self.readToEnd()
        }.value
    }
}