import Foundation
import OSLog

private extension Logger {
    static let lsCache = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "LSRegisterCache")
}

public actor LSRegisterCache {
    private struct Entry: Codable {
        let bundleID: String
        let url: Data
        let timestamp: Date
    }

    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 86400
    private let storageURL: URL

    public init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.storageURL = cachesDir.appendingPathComponent("com.macos-cleaner/lsregister.json")
        Task { await load() }
    }

    public func get(bundleID: String) -> URL? {
        guard let entry = cache[bundleID] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < ttl else {
            cache[bundleID] = nil
            return nil
        }
        do {
            let bookmarkData = entry.url
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            if isStale {
                cache[bundleID] = nil
                return nil
            }
            return url
        } catch {
            cache[bundleID] = nil
            return nil
        }
    }

    public func set(bundleID: String, url: URL) {
        guard let bookmarkData = try? url.bookmarkData() else { return }
        cache[bundleID] = Entry(bundleID: bundleID, url: bookmarkData, timestamp: Date())
        Task { await save() }
    }

    public func warmup() async {
        guard cache.isEmpty else { return }
        Logger.lsCache.info("Warming up LSRegisterCache")
        let appDirs = [
            NormalizedPath.url("/Applications", isDirectory: true),
            NormalizedPath.url(NormalizedPath.joinHome(NSHomeDirectory(), "Applications"), isDirectory: true),
        ]
        var entries: [String: Entry] = [:]
        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    if let bookmarkData = try? url.bookmarkData() {
                        entries[bundleID] = Entry(bundleID: bundleID, url: bookmarkData, timestamp: Date())
                    }
                }
            }
        }
        cache = entries
        Logger.lsCache.info("LSRegisterCache warmed with \(entries.count) entries")
        await save()
    }

    private func save() async {
        let entries = Array(cache.values)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        for entry in entries {
            cache[entry.bundleID] = entry
        }
        Logger.lsCache.info("Loaded \(entries.count) entries from LSRegisterCache on disk")
    }
}
