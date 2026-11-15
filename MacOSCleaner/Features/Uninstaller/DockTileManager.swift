import Foundation
import OSLog

private extension Logger {
    static let dock = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "DockTileManager")
}

public enum DockTileManager {
    private static let dockDomainName = "com.apple.dock"
    private static let persistentAppsKeyName = "persistent-apps"

    /// Removes any Dock tile matching `appURL` (preferred) or `bundleID` from `com.apple.dock`
    /// and restarts the Dock only if at least one tile was removed.
    @discardableResult
    public static func removeFromDock(
        appURL: URL,
        bundleID: String?,
        commandRunner: any CommandRunning = CommandRunner()
    ) async -> Int {
        let dockDomain = dockDomainName as CFString
        let persistentAppsKey = persistentAppsKeyName as CFString
        guard let rawEntries = CFPreferencesCopyAppValue(persistentAppsKey, dockDomain) as? [[String: Any]] else {
            return 0
        }

        let (updated, removedCount) = filterPersistentApps(rawEntries, appURL: appURL, bundleID: bundleID)
        guard removedCount > 0 else { return 0 }

        CFPreferencesSetAppValue(persistentAppsKey, updated as CFArray, dockDomain)
        CFPreferencesAppSynchronize(dockDomain)

        do {
            _ = try await commandRunner.run(command: "/usr/bin/killall", arguments: ["Dock"])
            Logger.dock.info("Removed \(removedCount) Dock tile(s) for \(appURL.lastPathComponent, privacy: .public)")
        } catch {
            Logger.dock.warning("killall Dock failed: \(error.localizedDescription, privacy: .public)")
        }
        return removedCount
    }

    /// Pure helper for filtering `persistent-apps` Dock entries.
    public static func filterPersistentApps(
        _ entries: [[String: Any]],
        appURL: URL,
        bundleID: String?
    ) -> (updated: [[String: Any]], removedCount: Int) {
        let targetPath = appURL.standardizedFileURL.path
        let targetBundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Count how many tiles share targetBundleID so we only fall back to bundleID when unique.
        let bundleMatchCount: Int
        if let targetBundleID, !targetBundleID.isEmpty {
            bundleMatchCount = entries.filter { tileBundleID($0) == targetBundleID }.count
        } else {
            bundleMatchCount = 0
        }

        var updated: [[String: Any]] = []
        updated.reserveCapacity(entries.count)
        var removedCount = 0

        for entry in entries {
            if let entryPath = tileAppPath(entry), entryPath == targetPath {
                removedCount += 1
                continue
            }
            if bundleMatchCount == 1,
               let targetBundleID,
               let entryBundleID = tileBundleID(entry),
               entryBundleID == targetBundleID {
                removedCount += 1
                continue
            }
            updated.append(entry)
        }

        return (updated, removedCount)
    }

    private static func tileAppPath(_ entry: [String: Any]) -> String? {
        guard let tileData = entry["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String else {
            return nil
        }
        if let url = URL(string: urlString), url.isFileURL {
            return url.standardizedFileURL.path
        }
        return URL(fileURLWithPath: urlString).standardizedFileURL.path
    }

    private static func tileBundleID(_ entry: [String: Any]) -> String? {
        guard let tileData = entry["tile-data"] as? [String: Any],
              let bid = tileData["bundle-identifier"] as? String else {
            return nil
        }
        let trimmed = bid.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
