import Foundation

/// Адаптер для взаимодействия с shell-скриптом очистки.
public final class ShellCleanupAdapter: Sendable {
    private let commandRunner: CommandRunner
    private let scriptPath: String
    
    public init(commandRunner: CommandRunner, scriptPath: String? = nil) {
        self.commandRunner = commandRunner
        
        if let providedPath = scriptPath {
            self.scriptPath = providedPath
        } else if let bundlePath = Bundle.main.path(forResource: "macos-cache-cleanup", ofType: "sh", inDirectory: "Scripts") {
            self.scriptPath = bundlePath
        } else {
            // Путь по умолчанию для разработки
            self.scriptPath = "/Users/alex/Documents/my/macos-cleaner/MacOSCleaner/Resources/Scripts/macos-cache-cleanup.sh"
        }
    }
    
    /// События, генерируемые скриптом.
    public enum CleanupEvent: Sendable {
        case step(current: Int, total: Int, title: String)
        case result(label: String, freed: Int)
        case preview(label: String, size: Int)
    }
    
    /// Запускает очистку.
    /// - Parameters:
    ///   - dryRun: Если true, запускает в режиме превью.
    /// - Returns: Стрим событий очистки.
    public func runCleanup(dryRun: Bool = false) -> AsyncThrowingStream<CleanupEvent, Error> {
        let args = dryRun ? ["--json", "--dry-run"] : ["--json"]
        let path = self.scriptPath
        let runner = self.commandRunner
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = runner.runStreaming(command: path, arguments: args)
                    for try await line in stream {
                        if let event = Self.parseLine(line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    private static func parseLine(_ line: String) -> CleanupEvent? {
        // Убираем возможные пробелы
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { return nil }
        
        guard let data = trimmed.data(using: .utf8) else { return nil }
        
        struct RawEvent: Codable {
            let type: String
            let current: Int?
            let total: Int?
            let title: String?
            let label: String?
            let freed: Int?
            let size: Int?
        }
        
        do {
            let raw = try JSONDecoder().decode(RawEvent.self, from: data)
            switch raw.type {
            case "step":
                if let c = raw.current, let t = raw.total, let title = raw.title {
                    return .step(current: c, total: t, title: title)
                }
            case "result":
                if let l = raw.label, let f = raw.freed {
                    return .result(label: l, freed: f)
                }
            case "preview":
                if let l = raw.label, let s = raw.size {
                    return .preview(label: l, size: s)
                }
            default:
                return nil
            }
        } catch {
            return nil
        }
        return nil
    }
}
