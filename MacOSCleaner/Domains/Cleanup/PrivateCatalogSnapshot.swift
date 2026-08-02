import AppKit
import Foundation
import OSLog

private extension Logger {
    static let privateCatalog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner",
        category: "PrivateCatalog"
    )
}

public enum CatalogSource: String, Sendable, Equatable {
    case privateAsset
    case publicFallback
}

/// UI metadata row carried by the private catalog (Domains-local; mapped by UIMetadataProvider).
public struct CatalogUIEntry: Sendable, Equatable {
    public let key: String
    public let name: String
    public let difficulty: String
    public let knownIssues: [String]
    public let parentSuite: String?
}

/// Immutable indexes built from the private catalog asset (or empty public fallback).
public struct PrivateCatalogSnapshot: Sendable {
    public let source: CatalogSource
    public let engineHash: String
    public let uiHash: String
    public let watermarks: [String]
    public let registry: [String: AppPaths]
    public let toolchains: [String: AppPaths]
    public let bundleIDToRegistryKey: [String: String]
    public let prefixIndex: [(prefix: String, key: String)]
    public let cachePathsByCategory: [CleanupCategory: [CleanupPath]]
    public let uiEntries: [String: CatalogUIEntry]
    public let uiBundleIDToKey: [String: String]
    public let uiPrefixIndex: [(prefix: String, key: String)]

    public static let empty = PrivateCatalogSnapshot(
        source: .publicFallback,
        engineHash: "",
        uiHash: "",
        watermarks: [],
        registry: [:],
        toolchains: [:],
        bundleIDToRegistryKey: [:],
        prefixIndex: [],
        cachePathsByCategory: [:],
        uiEntries: [:],
        uiBundleIDToKey: [:],
        uiPrefixIndex: []
    )

    public var isPrivate: Bool { source == .privateAsset }
}

// MARK: - Wire format (PropertyList + zlib)

enum PrivateCatalogFormat {
    static let assetName = "PrivateCleanupCatalog"
    static let formatVersion = 1
    static let magic = Data("MCC1".utf8)

    /// Provenance markers packed into the asset; never become cleanup paths.
    static let defaultWatermarks: [String] = [
        "com.macos-cleaner.provenance.canary.alpha",
        "com.macos-cleaner.provenance.canary.beta",
        "com.macos-cleaner.provenance.canary.gamma",
        "com.macos-cleaner.provenance.canary.delta",
        "com.macos-cleaner.provenance.canary.epsilon",
        "com.macos-cleaner.provenance.canary.zeta",
        "com.macos-cleaner.provenance.canary.eta",
        "com.macos-cleaner.provenance.canary.theta",
        "com.macos-cleaner.provenance.canary.iota",
        "com.macos-cleaner.provenance.canary.kappa",
        "com.macos-cleaner.provenance.canary.lambda",
        "com.macos-cleaner.provenance.canary.mu",
    ]
}

struct PrivateCatalogWire: Codable, Equatable {
    var formatVersion: Int
    var engineHash: String
    var uiHash: String
    var watermarks: [String]
    var apps: [PrivateCatalogWireApp]
    var toolchains: [PrivateCatalogWireApp]
    var uiApps: [PrivateCatalogWireUI]
    var uiToolchains: [PrivateCatalogWireUI]
}

struct PrivateCatalogWireApp: Codable, Equatable {
    var key: String
    var bundleIDs: [String]
    var bundleIDPrefixes: [String]
    var category: String
    var paths: [PrivateCatalogWirePath]
}

struct PrivateCatalogWirePath: Codable, Equatable {
    var template: String
    var purpose: String
    var isGlob: Bool
    var requiresAdmin: Bool
}

struct PrivateCatalogWireUI: Codable, Equatable {
    var key: String
    var name: String
    var difficulty: String
    var knownIssues: [String]
    var bundleIDs: [String]
    var bundleIDPrefixes: [String]
    var parentSuite: String?
}

enum PrivateCatalogCodec {
    static func encodeAsset(_ wire: PrivateCatalogWire) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let plist = try encoder.encode(wire)
        let compressed = try (plist as NSData).compressed(using: .zlib) as Data
        var output = PrivateCatalogFormat.magic
        output.append(compressed)
        return output
    }

    static func decodeAsset(_ data: Data) throws -> PrivateCatalogWire {
        guard data.count > PrivateCatalogFormat.magic.count else {
            throw PrivateCatalogError.invalidMagic
        }
        let magic = data.prefix(PrivateCatalogFormat.magic.count)
        guard magic == PrivateCatalogFormat.magic else {
            throw PrivateCatalogError.invalidMagic
        }
        let compressed = data.dropFirst(PrivateCatalogFormat.magic.count)
        let plist = try (compressed as NSData).decompressed(using: .zlib) as Data
        let wire = try PropertyListDecoder().decode(PrivateCatalogWire.self, from: plist)
        guard wire.formatVersion == PrivateCatalogFormat.formatVersion else {
            throw PrivateCatalogError.unsupportedVersion(wire.formatVersion)
        }
        return wire
    }

    static func snapshot(from wire: PrivateCatalogWire, source: CatalogSource) -> PrivateCatalogSnapshot {
        var registry: [String: AppPaths] = [:]
        var toolchains: [String: AppPaths] = [:]
        var bundleIDToRegistryKey: [String: String] = [:]
        var prefixIndex: [(prefix: String, key: String)] = []
        var cacheByCategory: [CleanupCategory: Set<String>] = [:]

        func ingest(_ entry: PrivateCatalogWireApp, into target: inout [String: AppPaths], indexBundles: Bool) {
            guard let category = CleanupCategory(rawValue: entry.category) else { return }
            let paths = entry.paths.compactMap { path -> RegistryPath? in
                guard let purpose = PathPurpose(rawValue: path.purpose) else { return nil }
                return RegistryPath(
                    template: path.template,
                    purpose: purpose,
                    isGlob: path.isGlob,
                    requiresAdmin: path.requiresAdmin
                )
            }
            let appPaths = AppPaths(
                bundleIDs: entry.bundleIDs,
                bundleIDPrefixes: entry.bundleIDPrefixes,
                paths: paths,
                category: category
            )
            target[entry.key] = appPaths

            for path in paths where path.purpose == .cache {
                let expanded = tildePath(path.template)
                cacheByCategory[category, default: []].insert(expanded)
            }

            guard indexBundles else { return }
            for bundleID in entry.bundleIDs {
                bundleIDToRegistryKey[bundleID.lowercased()] = entry.key
            }
            if entry.bundleIDs.isEmpty {
                bundleIDToRegistryKey[entry.key.lowercased()] = entry.key
            }
            for prefix in entry.bundleIDPrefixes {
                let normalized = prefix.lowercased()
                guard !normalized.isEmpty else { continue }
                prefixIndex.append((normalized, entry.key))
            }
        }

        for entry in wire.apps {
            ingest(entry, into: &registry, indexBundles: true)
        }
        for entry in wire.toolchains {
            ingest(entry, into: &toolchains, indexBundles: false)
        }

        prefixIndex.sort { lhs, rhs in
            if lhs.prefix.count != rhs.prefix.count { return lhs.prefix.count > rhs.prefix.count }
            return lhs.prefix < rhs.prefix
        }

        var cachePathsByCategory: [CleanupCategory: [CleanupPath]] = [:]
        for (category, paths) in cacheByCategory {
            cachePathsByCategory[category] = paths.sorted().map { path in
                CleanupPath(path: path, category: category, requiresSudo: requiresSudo(expanded: path))
            }
        }

        var uiEntries: [String: CatalogUIEntry] = [:]
        var uiBundleIDToKey: [String: String] = [:]
        var uiPrefixIndex: [(prefix: String, key: String)] = []

        func ingestUI(_ entry: PrivateCatalogWireUI) {
            uiEntries[entry.key] = CatalogUIEntry(
                key: entry.key,
                name: entry.name,
                difficulty: entry.difficulty,
                knownIssues: entry.knownIssues,
                parentSuite: entry.parentSuite
            )
            for bundleID in entry.bundleIDs {
                uiBundleIDToKey[bundleID.lowercased()] = entry.key
            }
            if entry.bundleIDs.isEmpty {
                uiBundleIDToKey[entry.key.lowercased()] = entry.key
            }
            for prefix in entry.bundleIDPrefixes {
                let normalized = prefix.lowercased()
                guard !normalized.isEmpty else { continue }
                uiPrefixIndex.append((normalized, entry.key))
            }
        }

        for entry in wire.uiApps { ingestUI(entry) }
        for entry in wire.uiToolchains { ingestUI(entry) }

        uiPrefixIndex.sort { lhs, rhs in
            if lhs.prefix.count != rhs.prefix.count { return lhs.prefix.count > rhs.prefix.count }
            return lhs.prefix < rhs.prefix
        }

        return PrivateCatalogSnapshot(
            source: source,
            engineHash: wire.engineHash,
            uiHash: wire.uiHash,
            watermarks: wire.watermarks,
            registry: registry,
            toolchains: toolchains,
            bundleIDToRegistryKey: bundleIDToRegistryKey,
            prefixIndex: prefixIndex,
            cachePathsByCategory: cachePathsByCategory,
            uiEntries: uiEntries,
            uiBundleIDToKey: uiBundleIDToKey,
            uiPrefixIndex: uiPrefixIndex
        )
    }

    private static let tokenReplacements: [(token: String, value: String)] = [
        ("<APP_SUPPORT>", "~/Library/Application Support"),
        ("<CACHES>", "~/Library/Caches"),
        ("<PREFS>", "~/Library/Preferences"),
        ("<CONTAINERS>", "~/Library/Containers"),
        ("<GROUP_CONTAINERS>", "~/Library/Group Containers"),
        ("<LOGS>", "~/Library/Logs"),
        ("<SAVED_STATE>", "~/Library/Saved Application State"),
        ("<USER_LIB>", "~/Library"),
        ("<USER_CONFIG>", "~/.config"),
        ("<USER_CACHE>", "~/.cache"),
        ("<USER_LOCAL_SHARE>", "~/.local/share"),
        ("<VAR_FOLDERS>", "/private/var/folders"),
        ("<SYS_LIB>", "/Library"),
        ("<SYS_APP_SUPPORT>", "/Library/Application Support"),
        ("<SYS_LAUNCH_AGENTS>", "/Library/LaunchAgents"),
        ("<SYS_LAUNCH_DAEMONS>", "/Library/LaunchDaemons"),
        ("<SYS_PRIV_HELPERS>", "/Library/PrivilegedHelperTools"),
        ("<SYS_CACHES>", "/Library/Caches"),
        ("<SYS_PREFS>", "/Library/Preferences"),
        ("<SYS_LOGS>", "/Library/Logs"),
        ("<HOME>", "~"),
    ]

    static func tildePath(_ template: String) -> String {
        var result = template
        for (token, value) in tokenReplacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }

    static func requiresSudo(expanded path: String) -> Bool {
        path.hasPrefix("/Library/")
            || path.hasPrefix("/private/")
            || path.hasPrefix("/usr/local/")
            || path.hasPrefix("/opt/homebrew/")
            || path.hasPrefix("/var/")
    }

    static func requiresAdmin(template: String, systemFlag: Bool) -> Bool {
        if systemFlag { return true }
        return requiresSudo(expanded: tildePath(template))
    }
}

enum PrivateCatalogError: Error {
    case invalidMagic
    case unsupportedVersion(Int)
    case missingAsset
}

enum PrivateCatalogLoader {
    /// Loads the private asset from the given bundle, or returns nil on any failure.
    static func load(bundle: Bundle = .main) -> PrivateCatalogSnapshot? {
        guard let asset = NSDataAsset(name: PrivateCatalogFormat.assetName, bundle: bundle) else {
            Logger.privateCatalog.debug("Private catalog asset missing — public fallback")
            return nil
        }
        do {
            let wire = try PrivateCatalogCodec.decodeAsset(asset.data)
            return PrivateCatalogCodec.snapshot(from: wire, source: .privateAsset)
        } catch {
            Logger.privateCatalog.error(
                "Private catalog decode failed: \(String(describing: error), privacy: .public) — public fallback"
            )
            return nil
        }
    }
}

/// Process-wide catalog snapshot. Fail-closed: any load error yields empty public fallback.
enum PrivateCatalogStore {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var cached: PrivateCatalogSnapshot?
        var overrideSnapshot: PrivateCatalogSnapshot?
    }

    private static let state = State()

    static var snapshot: PrivateCatalogSnapshot {
        state.lock.lock()
        defer { state.lock.unlock() }
        if let override = state.overrideSnapshot { return override }
        if let cached = state.cached { return cached }
        let loaded = PrivateCatalogLoader.load() ?? .empty
        state.cached = loaded
        return loaded
    }

    /// Test seam — inject a snapshot (nil clears override and cache).
    static func setOverrideForTesting(_ snapshot: PrivateCatalogSnapshot?) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.overrideSnapshot = snapshot
        state.cached = nil
    }

    static func resetForTesting() {
        setOverrideForTesting(nil)
    }

    static var requiresPrivateCatalog: Bool {
        ProcessInfo.processInfo.environment["REQUIRE_PRIVATE_CATALOG"] == "YES"
    }
}
