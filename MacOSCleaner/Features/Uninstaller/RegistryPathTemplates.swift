import Foundation

/// Tilde-normalized registry path templates for uninstaller tests and diagnostics.
public enum RegistryPathTemplates {
    /// SIP / system apps excluded from uninstaller registry lookup (legacy catalog behavior).
    private static let excludedBundleIDs: Set<String> = ["com.apple.safari"]

    private static let tokenToTilde: [(String, String)] = [
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

    /// Uninstaller-visible templates: cache + app data, no shared/admin paths.
    public static func uninstallTemplates(forBundleID bundleID: String) -> [String] {
        let lower = bundleID.lowercased()
        guard !lower.isEmpty, !lower.hasPrefix("unknown."), !excludedBundleIDs.contains(lower) else {
            return []
        }
        guard let appPaths = GeneratedCleanupPaths.appPaths(forBundleID: bundleID) else { return [] }
        return appPaths.paths.compactMap { entry in
            guard entry.purpose == .cache || entry.purpose == .appData, !entry.requiresAdmin else { return nil }
            return tildeTemplate(entry.template)
        }
    }

    /// All registry templates for a bundle ID (any purpose, including shared/admin).
    public static func allTemplates(forBundleID bundleID: String) -> Set<String> {
        guard let appPaths = GeneratedCleanupPaths.appPaths(forBundleID: bundleID) else { return [] }
        return Set(appPaths.paths.map { tildeTemplate($0.template) })
    }

    public static func tildeTemplate(_ template: String) -> String {
        var result = template
        for (token, value) in tokenToTilde {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }
}
