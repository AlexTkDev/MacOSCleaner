import Foundation
import OSLog

private extension Logger {
    static let uiMetadata = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner",
        category: "UIMetadataProvider"
    )
}

public enum UninstallDifficulty: String, Sendable, Codable, CaseIterable {
    case critical
    case high
    case medium
    case low

    public var localizationKey: String {
        "uninstaller.metadata.difficulty.\(rawValue)"
    }
}

public struct UIMetadata: Sendable, Equatable {
    public let registryKey: String
    public let name: String
    public let difficulty: UninstallDifficulty
    public let knownIssues: [String]
    public let parentSuite: String?

    public init(
        registryKey: String,
        name: String,
        difficulty: UninstallDifficulty,
        knownIssues: [String],
        parentSuite: String?
    ) {
        self.registryKey = registryKey
        self.name = name
        self.difficulty = difficulty
        self.knownIssues = knownIssues
        self.parentSuite = parentSuite
    }
}

public actor UIMetadataProvider {
    public static let shared = UIMetadataProvider()

    private let bundle: Bundle
    private let resourceName: String
    private let fileURL: URL?

    private var entries: [String: UIMetadata]?
    private var bundleIDToKey: [String: String]?
    private var prefixIndex: [(prefix: String, key: String)]?

    public init(bundle: Bundle = .main, resourceName: String = "ui_metadata", fileURL: URL? = nil) {
        self.bundle = bundle
        self.resourceName = resourceName
        self.fileURL = fileURL
    }

    /// Lookup by any bundle ID listed in `bundle_ids`, with prefix fallback.
    public func metadata(forBundleID bundleID: String) -> UIMetadata? {
        let lower = bundleID.lowercased()
        guard !lower.isEmpty, !lower.hasPrefix("unknown.") else { return nil }
        loadIfNeeded()
        guard let bundleIDToKey, let entries else { return nil }
        if let key = bundleIDToKey[lower], let metadata = entries[key] {
            return metadata
        }
        guard let prefixIndex else { return nil }
        for entry in prefixIndex where lower.hasPrefix(entry.prefix) {
            if let metadata = entries[entry.key] {
                return metadata
            }
        }
        return nil
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }

        // Tests may inject a local JSON fixture.
        if let fileURL {
            loadFromJSONFile(fileURL)
            return
        }

        // Production host only: shared private catalog snapshot (optional).
        // Custom bundles (unit tests) must not silently pick up the app catalog.
        if bundle == .main {
            let snapshot = PrivateCatalogStore.snapshot
            if snapshot.isPrivate, !snapshot.uiEntries.isEmpty {
                var mapped: [String: UIMetadata] = [:]
                for (key, entry) in snapshot.uiEntries {
                    guard let difficulty = UninstallDifficulty(rawValue: entry.difficulty) else { continue }
                    mapped[key] = UIMetadata(
                        registryKey: entry.key,
                        name: entry.name,
                        difficulty: difficulty,
                        knownIssues: entry.knownIssues,
                        parentSuite: entry.parentSuite
                    )
                }
                entries = mapped
                bundleIDToKey = snapshot.uiBundleIDToKey
                prefixIndex = snapshot.uiPrefixIndex
                return
            }
        }

        // Legacy bundle JSON (should be excluded from Resources; kept for resilience).
        if let url = bundle.url(forResource: resourceName, withExtension: "json") {
            loadFromJSONFile(url)
            return
        }

        Logger.uiMetadata.debug("UI metadata unavailable — metadata disabled")
        entries = [:]
        bundleIDToKey = [:]
        prefixIndex = []
    }

    private func loadFromJSONFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(UIMetadataFile.self, from: data)
            let loaded = Self.buildIndexes(apps: file.apps, toolchains: file.toolchains ?? [:])
            entries = loaded.entries
            bundleIDToKey = loaded.bundleIDToKey
            prefixIndex = loaded.prefixIndex
        } catch {
            Logger.uiMetadata.error("Failed to load ui_metadata.json: \(error.localizedDescription, privacy: .public)")
            entries = [:]
            bundleIDToKey = [:]
            prefixIndex = []
        }
    }

    private struct UIMetadataFile: Decodable {
        let version: String
        let apps: [String: UIMetadataEntry]
        let toolchains: [String: UIMetadataEntry]?
    }

    private struct UIMetadataEntry: Decodable {
        let name: String
        let difficulty: UninstallDifficulty
        let known_issues: [String]
        let bundle_ids: [String]?
        let bundle_id_prefixes: [String]?
        let parent_suite: String?
    }

    private struct LoadedIndexes: Sendable {
        let entries: [String: UIMetadata]
        let bundleIDToKey: [String: String]
        let prefixIndex: [(prefix: String, key: String)]
    }

    private static func buildIndexes(
        apps: [String: UIMetadataEntry],
        toolchains: [String: UIMetadataEntry]
    ) -> LoadedIndexes {
        var entries: [String: UIMetadata] = [:]
        var bundleIDToKey: [String: String] = [:]
        var prefixIndex: [(prefix: String, key: String)] = []

        func ingest(key: String, entry: UIMetadataEntry) {
            entries[key] = UIMetadata(
                registryKey: key,
                name: entry.name,
                difficulty: entry.difficulty,
                knownIssues: entry.known_issues,
                parentSuite: entry.parent_suite
            )
            for bundleID in entry.bundle_ids ?? [] {
                bundleIDToKey[bundleID.lowercased()] = key
            }
            if (entry.bundle_ids ?? []).isEmpty {
                bundleIDToKey[key.lowercased()] = key
            }
            for prefix in entry.bundle_id_prefixes ?? [] {
                let normalized = prefix.lowercased()
                guard !normalized.isEmpty else { continue }
                prefixIndex.append((normalized, key))
            }
        }

        for (key, entry) in apps {
            ingest(key: key, entry: entry)
        }
        for (key, entry) in toolchains {
            ingest(key: key, entry: entry)
        }

        prefixIndex.sort { lhs, rhs in
            if lhs.prefix.count != rhs.prefix.count { return lhs.prefix.count > rhs.prefix.count }
            return lhs.prefix < rhs.prefix
        }

        return LoadedIndexes(entries: entries, bundleIDToKey: bundleIDToKey, prefixIndex: prefixIndex)
    }
}
