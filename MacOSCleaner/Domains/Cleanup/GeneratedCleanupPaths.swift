import Foundation

/// Public facade over the private catalog asset (or empty public fallback).
/// Callers keep using the same API as the former generated Swift dump.
public enum GeneratedCleanupPaths {
    public static var catalogSource: CatalogSource { PrivateCatalogStore.snapshot.source }

    public static var sourceHash: String { PrivateCatalogStore.snapshot.engineHash }

    public static var uiHash: String { PrivateCatalogStore.snapshot.uiHash }

    public static var watermarks: [String] { PrivateCatalogStore.snapshot.watermarks }

    public static var registry: [String: AppPaths] { PrivateCatalogStore.snapshot.registry }

    public static var toolchains: [String: AppPaths] { PrivateCatalogStore.snapshot.toolchains }

    public static var bundleIDToRegistryKey: [String: String] {
        PrivateCatalogStore.snapshot.bundleIDToRegistryKey
    }

    public static var prefixIndex: [(prefix: String, key: String)] {
        PrivateCatalogStore.snapshot.prefixIndex
    }

    public static var browserCaches: [CleanupPath] { cachePaths(for: .browserCaches) }
    public static var ideCaches: [CleanupPath] { cachePaths(for: .ideCaches) }
    public static var appCaches: [CleanupPath] { cachePaths(for: .appCaches) }
    public static var dotfileCaches: [CleanupPath] { cachePaths(for: .dotfileCaches) }
    public static var userLogs: [CleanupPath] { cachePaths(for: .userLogs) }
    public static var messagingMedia: [CleanupPath] { cachePaths(for: .messagingMedia) }
    public static var languageCaches: [CleanupPath] { cachePaths(for: .languageCaches) }
    public static var systemCaches: [CleanupPath] { cachePaths(for: .systemCaches) }

    public static func appPaths(forBundleID bundleID: String) -> AppPaths? {
        let lower = bundleID.lowercased()
        guard !lower.isEmpty, !lower.hasPrefix("unknown.") else { return nil }
        let snapshot = PrivateCatalogStore.snapshot
        if let key = snapshot.bundleIDToRegistryKey[lower], let paths = snapshot.registry[key] {
            return paths
        }
        for entry in snapshot.prefixIndex where lower.hasPrefix(entry.prefix) {
            if let paths = snapshot.registry[entry.key] { return paths }
        }
        return nil
    }

    public static func cachePaths(for category: CleanupCategory) -> [CleanupPath] {
        paths(for: category)
    }

    public static func paths(for category: CleanupCategory) -> [CleanupPath] {
        PrivateCatalogStore.snapshot.cachePathsByCategory[category] ?? []
    }
}
