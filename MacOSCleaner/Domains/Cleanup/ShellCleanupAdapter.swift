import Foundation

/// Адаптер для взаимодействия с shell-скриптом очистки.
public final class ShellCleanupAdapter: Sendable {
    private let commandRunner: CommandRunner
    private let scriptPath: String
    
    public init(commandRunner: CommandRunner, scriptPath: String? = nil) {
        self.commandRunner = commandRunner
        
        if let providedPath = scriptPath {
            self.scriptPath = providedPath
        } else if let bundlePath = Bundle.main.path(forResource: "macos-cache-cleanup", ofType: "sh") {
            // Xcode кладёт скрипт плоско в Contents/Resources (без подпапки)
            self.scriptPath = bundlePath
        } else {
            // Путь для запуска из Xcode в режиме разработки
            self.scriptPath = "/Users/alex/Documents/my/macos-cleaner/MacOSCleaner/Resources/Scripts/macos-cache-cleanup.sh"
        }
    }
    
    /// События, генерируемые скриптом.
    public enum CleanupEvent: Sendable {
        case step(current: Int, total: Int, title: String)
        case result(label: String, freed: Int)
        case preview(label: String, size: Int, deletable: Bool, parent: String?, description: String?)
        case log(String)
    }
    
    public struct CleanupOptions: Sendable, Equatable {
        public var cleanModCache: Bool = false
        public var cleanMaven: Bool = false
        public var cleanProjects: Bool = false
        public var cleanDSStore: Bool = false
        public init() {}
    }
    
    /// Запускает очистку.
    /// - Parameters:
    ///   - scanOnly: Если true, запускает глубокое сканирование без удаления (--scan).
    ///   - dryRun: Если true, запускает в режиме превью (--dry-run).
    ///   - options: Дополнительные опции очистки.
    /// - Returns: Стрим событий очистки.
    public func runCleanup(
        scanOnly: Bool = false,
        dryRun: Bool = false,
        options: CleanupOptions = .init(),
        selectedPaths: [String]? = nil
    ) -> AsyncThrowingStream<CleanupEvent, Error> {
        let scriptPath = self.scriptPath
        let runner = self.commandRunner
        let path = "/bin/bash"
        
        var baseArgs = Self.buildArgs(scanOnly: scanOnly, dryRun: dryRun, options: options)
        
        var tempFile: URL? = nil
        if let selected = selectedPaths, !selected.isEmpty {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "cleanup_paths_\(UUID().uuidString).txt"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try? selected.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            tempFile = fileURL
            baseArgs.append("--paths-file")
            baseArgs.append(fileURL.path)
        }
        
        let args = [scriptPath] + baseArgs
        
        return AsyncThrowingStream { continuation in
            let task = Task { [args, runner, path, tempFile] in
                do {
                    let stream = runner.runStreaming(command: path, arguments: args)
                    for try await line in stream {
                        if let event = Self.parseLine(line) {
                            continuation.yield(event)
                        }
                    }
                    
                    // Cleanup temp file
                    if let file = tempFile {
                        try? FileManager.default.removeItem(at: file)
                    }
                    
                    continuation.finish()
                } catch {
                    if let file = tempFile {
                        try? FileManager.default.removeItem(at: file)
                    }
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    private static func buildArgs(scanOnly: Bool, dryRun: Bool, options: CleanupOptions) -> [String] {
        var args = ["--json"]
        if scanOnly {
            args.append("--scan")
        } else if dryRun {
            args.append("--dry-run")
        }
        if options.cleanModCache { args.append("--clean-modcache") }
        if options.cleanMaven { args.append("--clean-maven") }
        if options.cleanProjects { args.append("--clean-projects") }
        if options.cleanDSStore { args.append("--clean-ds-store") }
        return args
    }
    
    private static func parseLine(_ line: String) -> CleanupEvent? {
        // Убираем возможные префиксы от CommandRunner
        var processedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if processedLine.hasPrefix("[stderr] ") {
            processedLine = String(processedLine.dropFirst(9))
        } else if processedLine.hasPrefix("[debug] ") {
            processedLine = String(processedLine.dropFirst(8))
        }
        
        let trimmed = processedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("{") else { return .log(line) }
        
        guard let data = trimmed.data(using: .utf8) else { return .log(line) }
        
        struct RawEvent: Codable {
            let type: String
            let current: Int?
            let total: Int?
            let title: String?
            let label: String?
            let freed: Int?
            let size: Int?
            let deletable: Bool?
            let parent: String?
            let description: String?
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
                    return .preview(label: l, size: s, deletable: raw.deletable ?? true, parent: raw.parent, description: raw.description)
                }
            default:
                return .log(line)
            }
        } catch {
            return .log(line)
        }
        return .log(line)
    }
}
