import Foundation

/// Folds helper / Electron Helper sidebar entries into their parent app so one
/// uninstall covers the main bundle plus helper residuals.
public enum HelperAppCollapser {
    public struct Result: Sendable {
        public let apps: [UninstallerService.AppInfo]
        /// Parent bundle path → helper URLs absorbed (for deep-scan attachment).
        public let absorbedHelpers: [String: [URL]]
    }

    public static func collapse(_ apps: [UninstallerService.AppInfo]) -> Result {
        var absorbed: [String: [URL]] = [:]
        var kept: [UninstallerService.AppInfo] = []
        let nonHelpers = apps.filter { !isHelperApp($0) }

        for app in apps {
            guard isHelperApp(app) else {
                kept.append(app)
                continue
            }
            guard let parent = findParent(for: app, in: nonHelpers) else {
                kept.append(app)
                continue
            }
            let key = parent.url.standardizedFileURL.path
            var urls = absorbed[key] ?? []
            urls.append(app.url.standardizedFileURL)
            if let bundleID = app.bundleID, !bundleID.isEmpty {
                urls.append(contentsOf: darwinCacheURLs(forBundleID: bundleID))
            }
            absorbed[key] = urls
        }

        var mergedAbsorbed = absorbed
        let updated = kept.map { app -> UninstallerService.AppInfo in
            let key = app.url.standardizedFileURL.path
            guard let helperURLs = mergedAbsorbed.removeValue(forKey: key), !helperURLs.isEmpty else {
                return app
            }
            var copy = app
            var existing = Set(copy.absorbedHelperURLs.map { $0.standardizedFileURL.path })
            for url in helperURLs {
                let path = url.standardizedFileURL.path
                guard existing.insert(path).inserted else { continue }
                // Skip helper .app nested inside the parent bundle — deleting the parent covers it.
                if path.hasPrefix(key + "/") { continue }
                copy.absorbedHelperURLs.append(url.standardizedFileURL)
            }
            return copy
        }

        return Result(apps: updated, absorbedHelpers: absorbed)
    }

    public static func isHelperApp(_ app: UninstallerService.AppInfo) -> Bool {
        let id = (app.bundleID ?? "").lowercased()
        if id.hasSuffix(".helper") { return true }
        let name = app.name.lowercased()
        return name.contains(" helper") || name.hasSuffix("helper")
    }

    /// URL-only heuristic for discovery progress (before AppInfo exists).
    public static func isLikelyHelperURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path.lowercased()
        if path.contains("/contents/frameworks/") { return true }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if name.contains(" helper") || name.hasSuffix("helper") { return true }
        if let bundleID = Bundle(url: url)?.bundleIdentifier?.lowercased(),
           bundleID.hasSuffix(".helper") {
            return true
        }
        return false
    }

    public static func findParent(
        for helper: UninstallerService.AppInfo,
        in apps: [UninstallerService.AppInfo]
    ) -> UninstallerService.AppInfo? {
        let helperID = (helper.bundleID ?? "").lowercased()
        let helperPath = helper.url.standardizedFileURL.path

        if helperID.hasSuffix(".helper") {
            let parentID = String(helperID.dropLast(".helper".count))
            if let parent = apps.first(where: { ($0.bundleID ?? "").lowercased() == parentID }) {
                return parent
            }
        }

        if let parentPath = enclosingAppBundlePath(helperPath),
           let parent = apps.first(where: { $0.url.standardizedFileURL.path == parentPath }) {
            return parent
        }

        if helperID == "com.github.electron.helper" {
            let electronParents = apps.filter { $0.identity?.isElectron == true }
            if electronParents.count == 1 { return electronParents[0] }
            let helperName = helper.name.lowercased()
            if let match = electronParents.first(where: { helperName.hasPrefix($0.name.lowercased()) }) {
                return match
            }
        }

        for parent in apps {
            guard let helpers = parent.identity?.helperNames, !helpers.isEmpty else { continue }
            let helperName = helper.name.lowercased()
            if helpers.contains(where: { helperName.contains($0.lowercased()) || $0.lowercased().contains(helperName) }) {
                return parent
            }
        }

        return nil
    }

    /// `/Applications/Cursor.app/Contents/...` → `/Applications/Cursor.app`
    public static func enclosingAppBundlePath(_ path: String) -> String? {
        guard let range = path.range(of: ".app/", options: .caseInsensitive) else { return nil }
        return String(path[..<range.upperBound].dropLast())
    }

    private static func darwinCacheURLs(forBundleID bundleID: String) -> [URL] {
        let fm = FileManager.default
        let cacheRoot = fm.temporaryDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("C", isDirectory: true)
            .resolvingSymlinksInPath()
        guard let contents = try? fm.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let lower = bundleID.lowercased()
        return contents.filter {
            let name = $0.lastPathComponent.lowercased()
            return name == lower || name.hasPrefix(lower + ".")
        }
    }
}
