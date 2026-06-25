import Foundation
import OSLog

private extension Logger {
    static let snapshot = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "SnapshotStore")
}

public actor SnapshotStore {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let appSupport = storageURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageURL = appSupport.appendingPathComponent("MacOSCleaner/Snapshots", isDirectory: true)
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    private func fileURL(for id: UUID) -> URL {
        storageURL.appendingPathComponent("\(id.uuidString).json")
    }

    public func save(snapshot: UninstallSnapshot) throws {
        try ensureDirectory()
        let data = try encoder.encode(snapshot)
        let url = fileURL(for: snapshot.id)
        try data.write(to: url, options: .atomic)
        Logger.snapshot.info("Saved snapshot '\(snapshot.id.uuidString, privacy: .public)' for '\(snapshot.appName, privacy: .public)'")
    }

    public func load(id: UUID) throws -> UninstallSnapshot? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(UninstallSnapshot.self, from: data)
    }

    public func list() throws -> [UninstallSnapshot] {
        try ensureDirectory()
        let contents = try fileManager.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: [.creationDateKey])
        let jsonFiles = contents.filter { $0.pathExtension == "json" }
        var snapshots: [UninstallSnapshot] = []
        for url in jsonFiles {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(UninstallSnapshot.self, from: data) else {
                continue
            }
            snapshots.append(snapshot)
        }
        return snapshots.sorted { $0.timestamp > $1.timestamp }
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            Logger.snapshot.info("Deleted snapshot '\(id.uuidString, privacy: .public)'")
        }
    }

    public func snapshotCount() throws -> Int {
        try ensureDirectory()
        let contents = try fileManager.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: nil)
        return contents.filter { $0.pathExtension == "json" }.count
    }
}
