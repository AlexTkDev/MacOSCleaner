import Foundation
import OSLog

private extension Logger {
    static let lsCache = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "LSRegisterCache")
}

public actor LSRegisterCache {
    public static let shared = LSRegisterCache()

    private struct Entry {
        let url: URL
        let timestamp: Date
    }

    private struct IndexedPathEntry: Sendable {
        let path: String
        let lower: String
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 86400
    private var dumpedEntries: [IndexedPathEntry]? = nil
    private var inFlightDump: Task<[IndexedPathEntry], Never>? = nil

    public init() {}

    public func paths(matching bundleID: String, commandRunner: CommandRunner = CommandRunner()) async -> Set<URL> {
        let bundleIDLower = bundleID.lowercased()
        guard !bundleIDLower.isEmpty, !bundleIDLower.hasPrefix("unknown.") else { return [] }

        let entries: [IndexedPathEntry]
        if let cached = dumpedEntries {
            entries = cached
        } else if let existingTask = inFlightDump {
            entries = await existingTask.value
        } else {
            let task = Task<[IndexedPathEntry], Never> {
                let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
                guard FileManager.default.fileExists(atPath: lsregister),
                      let result = try? await commandRunner.run(command: lsregister, arguments: ["-dump"]) else {
                    return []
                }
                var parsed: [IndexedPathEntry] = []
                autoreleasepool {
                    result.stdout.enumerateLines { line, _ in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("path:") else { return }
                        let p = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if !p.isEmpty {
                            parsed.append(IndexedPathEntry(path: p, lower: p.lowercased()))
                        }
                    }
                }
                Logger.lsCache.info("Cached \(parsed.count) path entries from lsregister -dump")
                return parsed
            }
            inFlightDump = task
            let parsed = await task.value
            dumpedEntries = parsed
            inFlightDump = nil
            entries = parsed
        }

        var found = Set<URL>()
        for entry in entries where entry.lower.contains(bundleIDLower) {
            found.insert(NormalizedPath.url(entry.path))
        }
        return found
    }

    public func get(bundleID: String) -> URL? {
        guard let entry = cache[bundleID] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < ttl else {
            cache[bundleID] = nil
            return nil
        }
        return entry.url
    }

    public func set(bundleID: String, url: URL) {
        cache[bundleID] = Entry(url: url, timestamp: Date())
    }
}
