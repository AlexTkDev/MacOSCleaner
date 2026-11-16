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

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 86400
    private var dumpedPaths: [String]? = nil

    public init() {}

    public func paths(matching bundleID: String, commandRunner: CommandRunner = CommandRunner()) async -> Set<URL> {
        let bundleIDLower = bundleID.lowercased()
        guard !bundleIDLower.isEmpty, !bundleIDLower.hasPrefix("unknown.") else { return [] }

        if dumpedPaths == nil {
            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
            guard FileManager.default.fileExists(atPath: lsregister),
                  let result = try? await commandRunner.run(command: lsregister, arguments: ["-dump"]) else {
                dumpedPaths = []
                return []
            }
            var paths: [String] = []
            for line in result.stdout.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("path:") else { continue }
                let p = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !p.isEmpty {
                    paths.append(p)
                }
            }
            dumpedPaths = paths
            Logger.lsCache.info("Cached \(paths.count) path entries from lsregister -dump")
        }

        guard let paths = dumpedPaths else { return [] }
        var found = Set<URL>()
        for path in paths {
            if path.lowercased().contains(bundleIDLower) {
                found.insert(NormalizedPath.url(path))
            }
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
