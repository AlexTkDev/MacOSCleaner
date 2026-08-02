import Foundation

public struct CandidateCollection: Sendable {
    public let candidates: Set<URL>
    /// Subset of `candidates` owned by a package-manager receipt — guaranteed app files.
    public let receiptPaths: Set<URL>
    /// Subset from GeneratedCleanupPaths registry — high-confidence curated residuals (cache only).
    public let catalogPaths: Set<URL>
    /// Shared components (Keystone, AutoUpdate, …) — informational only, never auto-deleted.
    public let sharedPaths: Set<URL>
    /// User content / models — shown for review, never preselected.
    public let informationalPaths: Set<URL>
}

public actor CandidateCollector {
    private let fileManager: FileManager
    private let commandRunner: any CommandRunning
    private let homebrewCellarDirectories: [URL]
    /// Current-user Darwin dirs (`…/C`, `…/T`, `…/X`). Tests may inject a single root.
    private let darwinUserDirectories: [URL]
    private let receiptsDirectory: URL
    private let tmpScanDirectory: URL
    private let fileSystemContext: FileSystemContext

    private static let homeResidualDenyList: Set<String> = [
        ".ssh", ".gnupg", ".Trash", ".trash", ".CFUserTextEncoding",
        ".DS_Store", ".localized", "Library", "Documents", "Desktop",
        "Downloads", "Movies", "Music", "Pictures", "Public", "Applications",
    ]

    public init(
        fileManager: FileManager = .default,
        commandRunner: any CommandRunning = CommandRunner(),
        homebrewCellarDirectories: [URL] = AppDiscovery.defaultHomebrewCellarDirectories,
        darwinCacheDirectory: URL? = nil,
        receiptsDirectory: URL? = nil,
        tmpScanDirectory: URL? = nil,
        fileSystemContext: FileSystemContext = .production
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.homebrewCellarDirectories = homebrewCellarDirectories
        self.fileSystemContext = fileSystemContext
        if let darwinCacheDirectory {
            self.darwinUserDirectories = [darwinCacheDirectory.resolvingSymlinksInPath()]
        } else {
            let parent = fileManager.temporaryDirectory
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
            self.darwinUserDirectories = ["C", "T", "X"].map {
                parent.appendingPathComponent($0, isDirectory: true)
            }
        }
        self.receiptsDirectory = (receiptsDirectory
            ?? URL(fileURLWithPath: "/private/var/db/receipts", isDirectory: true))
            .resolvingSymlinksInPath()
        self.tmpScanDirectory = (tmpScanDirectory
            ?? URL(fileURLWithPath: "/private/tmp", isDirectory: true))
            .resolvingSymlinksInPath()
    }

    public func collect(identity: AppIdentity, mode: ScanMode = .balanced) async -> Set<URL> {
        await collectDetailed(identity: identity, mode: mode).candidates
    }

    public func collectDetailed(identity: AppIdentity, mode: ScanMode = .balanced) async -> CandidateCollection {
        var candidates = Set<URL>()
        let home = fileSystemContext.homePath
        let maxDepth = mode == .safe ? 3 : 5

        // 1. Fixed popular paths
        let basePaths = [
            NormalizedPath.joinHome(home, "Library/Application Support"),
            NormalizedPath.joinHome(home, "Library/Caches"),
            NormalizedPath.joinHome(home, "Library/Containers"),
            NormalizedPath.joinHome(home, "Library/Group Containers"),
            NormalizedPath.joinHome(home, "Library/Preferences"),
            NormalizedPath.joinHome(home, "Library/Preferences/ByHost"),
            NormalizedPath.joinHome(home, "Library/HTTPStorages"),
            NormalizedPath.joinHome(home, "Library/WebKit"),
            NormalizedPath.joinHome(home, "Library/Saved Application State"),
            NormalizedPath.joinHome(home, "Library/Application Scripts"),
            NormalizedPath.joinHome(home, "Library/Logs"),
            NormalizedPath.joinHome(home, "Library/Logs/DiagnosticReports"),
            NormalizedPath.joinHome(home, "Library/Cookies"),
            NormalizedPath.joinHome(home, "Library/Internet Plug-Ins"),
            NormalizedPath.joinHome(home, "Library/QuickLook"),
            NormalizedPath.joinHome(home, "Library/Application Support/CrashReporter"),
            NormalizedPath.joinHome(home, "Library/LaunchAgents"),
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Preferences",
            "/Library/Application Support",
            "/Library/Caches",
            "/Library/Logs",
            "/Library/PrivilegedHelperTools",
            "/Library/Internet Plug-Ins",
            "/Library/QuickLook",
            "/Library/Spotlight",
            "/Library/PreferencePanes",
            "/Library/Input Methods",
            "/Library/Logs/DiagnosticReports",
            "/Library/Audio/Plug-Ins/HAL",
            "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST",
            "/Library/Audio/Plug-Ins/VST3",
            NormalizedPath.joinHome(home, "Library/Developer"),
            NormalizedPath.joinHome(
                home,
                "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"
            ),
            // User Library plugins/extensions
            NormalizedPath.joinHome(home, "Library/Screen Savers"),
            NormalizedPath.joinHome(home, "Library/Services"),
            NormalizedPath.joinHome(home, "Library/Frameworks"),
            NormalizedPath.joinHome(home, "Library/ColorPickers"),
            NormalizedPath.joinHome(home, "Library/Address Book Plug-Ins"),
            NormalizedPath.joinHome(home, "Library/Mail/Bundles"),
            NormalizedPath.joinHome(home, "Library/Keyboard Layouts"),
            NormalizedPath.joinHome(home, "Library/Dictionaries"),
            NormalizedPath.joinHome(home, "Library/PreferencePanes"),
            // System heuristic directories
            "/Library/Frameworks",
            "/Library/Screen Savers",
            "/Library/ColorPickers",
            "/Library/Extensions",
            "/Library/Services",
        ]

        for base in basePaths {
            let url = NormalizedPath.url(base, isDirectory: true)
            candidates.formUnion(await shallowScan(url, identity: identity, mode: mode))
        }

        // XDG dirs — CLI/Electron app configs (heuristic — public fallback)
        for relative in [".config", ".cache", ".local/share"] {
            let xdgPath = NormalizedPath.joinHome(home, relative)
            if fileManager.fileExists(atPath: xdgPath) {
                let xdgURL = NormalizedPath.url(xdgPath, isDirectory: true)
                candidates.formUnion(await shallowScan(xdgURL, identity: identity, mode: mode))
            }
        }

        // Current user's Darwin dirs (/private/var/folders/.../{C,T,X}).
        candidates.formUnion(collectDarwinUserDirs(identity: identity))

        // Installer receipt metadata on disk (.plist / .bom), in addition to pkgutil.
        candidates.formUnion(collectReceiptFiles(identity: identity))

        // 2. Deep scan critical folders
        let deepFolders = [
            NormalizedPath.joinHome(home, "Library/Application Support"),
            NormalizedPath.joinHome(home, "Library/Caches"),
            NormalizedPath.joinHome(home, "Library/Containers"),
            NormalizedPath.joinHome(home, "Library/Group Containers"),
            NormalizedPath.joinHome(home, "Library/HTTPStorages"),
            NormalizedPath.joinHome(home, "Library/WebKit"),
            NormalizedPath.joinHome(home, "Library/Preferences"),
            NormalizedPath.joinHome(home, "Library/Application Scripts"),
        ]
        for dir in deepFolders {
            let url = NormalizedPath.url(dir, isDirectory: true)
            candidates.formUnion(await deepScan(url, identity: identity, depth: 0, maxDepth: maxDepth, mode: mode))
        }

        // 3. Package-manager receipts. Homebrew can keep the same app bundle in
        // several versioned formulae (python@3.12 and python@3.14).
        let receiptPaths = await collectPkgutilReceiptPaths(identity: identity)
        candidates.formUnion(receiptPaths)

        // Homebrew sibling kegs: discover as candidates, never elevate to receiptPaths
        // (siblings stay candidates — deep scan preselects them for uninstall).
        let homebrewSiblings = collectHomebrewSiblingApps(identity: identity)
        candidates.formUnion(homebrewSiblings)

        // 4. Home residuals (dotdirs in ~) — always collected
        candidates.formUnion(collectHomeResiduals(identity: identity, home: home))

        // 5. mdfind (balanced only)
        if mode == .balanced {
            let mdfindCandidates = await runMdfind(identity: identity)
            candidates.formUnion(mdfindCandidates)
            candidates.formUnion(await collectTmpAppBundles(identity: identity))
            candidates.formUnion(await collectFromLSRegister(identity: identity))
        }

        // 5. App-specific Electron paths
        if identity.isElectron {
            let electronPath = NormalizedPath.joinHome(home, "Library/Application Support/\(identity.appName)")
            if fileManager.fileExists(atPath: electronPath) {
                candidates.insert(NormalizedPath.url(electronPath, isDirectory: true))
            }
        }

        // 6. JetBrains-specific (balanced only)
        if mode == .balanced, identity.isJetBrains {
            let jbPath = NormalizedPath.joinHome(home, "Library/Application Support/JetBrains")
            if fileManager.fileExists(atPath: jbPath) {
                let jbURL = NormalizedPath.url(jbPath, isDirectory: true)
                candidates.formUnion(await shallowScan(jbURL, identity: identity, mode: mode))
                candidates.formUnion(await deepScan(jbURL, identity: identity, depth: 0, maxDepth: maxDepth, mode: mode))
            }
        }

        // 7. Docker / OrbStack home dirs (heuristic; catalog may also list these officially)
        if identity.isDocker
            || identity.bundleID.lowercased().contains("orbstack")
            || identity.appName.lowercased().contains("orbstack") {
            for relative in [".docker", ".orbstack"] {
                let path = NormalizedPath.joinHome(home, relative)
                if fileManager.fileExists(atPath: path) {
                    candidates.insert(NormalizedPath.url(path, isDirectory: true))
                }
            }
        }

        if identity.isDocker {
            let dockerPaths = [
                NormalizedPath.joinHome(home, "Library/Containers/com.docker.docker"),
                NormalizedPath.joinHome(home, "Library/Group Containers/group.com.docker"),
            ]
            for p in dockerPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(NormalizedPath.url(p, isDirectory: true))
            }
        }

        // 8. Steam-specific
        if identity.bundleID == "com.valvesoftware.steam" || identity.appName == "Steam" {
            let steamPaths = [
                NormalizedPath.joinHome(home, "Library/Application Support/Steam"),
            ]
            for p in steamPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(NormalizedPath.url(p, isDirectory: true))
            }
        }

        // 9. Epic Games-specific
        if identity.bundleID == "com.epicgames.EpicGamesLauncher" || identity.appName.lowercased().contains("epic") {
            let epicPaths = [
                NormalizedPath.joinHome(home, "Library/Application Support/Epic"),
                NormalizedPath.joinHome(home, "Library/Application Support/Epic Games Launcher"),
            ]
            for p in epicPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(NormalizedPath.url(p, isDirectory: true))
            }
        }

        // 10. Unity-specific
        if identity.bundleID.lowercased().hasPrefix("com.unity3d.") || identity.appName == "Unity Hub" {
            let unityPaths = [
                NormalizedPath.joinHome(home, "Library/Application Support/Unity"),
                NormalizedPath.joinHome(home, "Library/Application Support/Unity Hub"),
                NormalizedPath.joinHome(home, ".local/share/unity3d"),
            ]
            for p in unityPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(NormalizedPath.url(p, isDirectory: true))
            }
        }

        // 11. Network extension / VPN-specific
        let isNetworkExt = identity.bundleID.lowercased().contains("littlesnitch") ||
            identity.bundleID.lowercased().contains("nordvpn") ||
            identity.bundleID.lowercased().contains("expressvpn") ||
            identity.appName.lowercased().contains("vpn") ||
            identity.appName.lowercased().contains("snitch")
        if isNetworkExt {
            let nePaths = [
                "/Library/SystemExtensions",
                "/Library/StagedExtensions",
                NormalizedPath.joinHome(home, "Library/Application Support/Little Snitch"),
                NormalizedPath.joinHome(home, "Library/Application Support/NordVPN"),
            ]
            for p in nePaths where fileManager.fileExists(atPath: p) {
                candidates.insert(NormalizedPath.url(p, isDirectory: true))
            }
        }

        // 12. VM / container user data outside ~/Library (OrbStack_files, Parallels, …)
        if isVirtualizationApp(identity) {
            candidates.formUnion(await scanVMUserData(identity: identity))
        }

        // 13. Browser vendor folders (Google/Chrome, Mozilla/Firefox, …)
        candidates.formUnion(await collectBrowserVendorPaths(identity: identity, home: home, maxDepth: maxDepth))

        // 14. Generated cleanup registry (exact/glob templates for known residuals)
        let registry = collectRegistryPaths(identity: identity, home: home)
        candidates.formUnion(registry.candidates)
        // Shared / user_content must never compete as selectable delete candidates.
        // Path-key subtract so file/dir URL forms of the same path both match.
        candidates = NormalizedPath.urls(candidates)
        candidates.subtract(NormalizedPath.urls(registry.sharedPaths))
        candidates.subtract(NormalizedPath.urls(registry.informationalPaths))

        // 15. Android Studio home tooling — after shared subtract so catalog
        // purpose:shared cannot drop ~/.gradle / ~/.android / Library/Android.
        let androidID = identity.bundleID.lowercased()
        if androidID.contains("android.studio") || identity.appName.lowercased().contains("android studio") {
            for relative in [".gradle", ".android", "Library/Android"] {
                let url = NormalizedPath.url(NormalizedPath.joinHome(home, relative))
                if fileManager.fileExists(atPath: url.path) {
                    candidates.insert(url)
                }
            }
        }

        candidates = NormalizedPath.urls(
            Set(candidates.filter { !Self.isForeignDeveloperTree($0, identity: identity) })
        )

        return CandidateCollection(
            candidates: candidates,
            receiptPaths: NormalizedPath.urls(Set(receiptPaths)),
            catalogPaths: NormalizedPath.urls(registry.catalogPaths),
            sharedPaths: NormalizedPath.urls(registry.sharedPaths),
            informationalPaths: NormalizedPath.urls(registry.informationalPaths)
        )
    }

    private func collectDarwinUserDirs(identity: AppIdentity) -> Set<URL> {
        var found = Set<URL>()
        for directory in darwinUserDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in contents where matchesDarwinEntry(item.lastPathComponent, identity: identity) {
                found.insert(NormalizedPath.canonicalize(item))
            }
        }
        return NormalizedPath.urls(found)
    }

    /// Bundle-ID / helper / savedState matching for Darwin C/T/X entries.
    private func matchesDarwinEntry(_ name: String, identity: AppIdentity) -> Bool {
        let lower = name.lowercased()
        let bundleID = identity.bundleID.lowercased()
        guard !bundleID.isEmpty, !bundleID.hasPrefix("unknown.") else { return false }

        if lower == bundleID || lower.hasPrefix(bundleID + ".") { return true }
        if lower.hasSuffix(".savedstate"), lower.hasPrefix(bundleID) { return true }

        for helper in identity.helperNames {
            let helperLower = helper.lowercased()
            guard helperLower.count >= 3 else { continue }
            if lower == helperLower || lower.hasPrefix(helperLower + ".") { return true }
            if lower == bundleID + ".helper" || lower.hasPrefix(bundleID + ".helper.") { return true }
        }

        // Prefix-only app name or username-prefixed (<username>-<appName>-*), never bare contains.
        let appName = identity.appName.lowercased()
        if appName.count >= 4 {
            if lower.hasPrefix(appName + "-") || lower.hasPrefix(appName + ".") || lower.hasPrefix(appName + "_") {
                return true
            }
            if lower.contains("-" + appName + "-") || lower.contains("-" + appName + ".") || lower.contains("-" + appName + "_") || lower.hasSuffix("-" + appName) {
                return true
            }
        }
        return false
    }

    /// On-disk pkg receipts (.plist / .bom) matched by bundle ID or sanitized app name.
    private func collectReceiptFiles(identity: AppIdentity) -> Set<URL> {
        let bundleID = identity.bundleID.lowercased()
        guard !bundleID.isEmpty, !bundleID.hasPrefix("unknown.") else { return [] }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: receiptsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sanitizedApp = identity.appName
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        var found = Set<URL>()
        for item in contents {
            let lower = item.lastPathComponent.lowercased()
            let stem = (lower as NSString).deletingPathExtension
            guard lower.hasSuffix(".plist") || lower.hasSuffix(".bom") else { continue }
            if stem == bundleID || stem.hasPrefix(bundleID + ".") || lower.contains(bundleID) {
                found.insert(NormalizedPath.canonicalize(item))
                continue
            }
            if sanitizedApp.count >= 4, stem.contains(sanitizedApp) || lower.contains(sanitizedApp) {
                found.insert(NormalizedPath.canonicalize(item))
            }
        }
        return NormalizedPath.urls(found)
    }

    /// Shallow home entries (dotdirs / top-level app folders). No curated private path list.
    private func collectHomeResiduals(identity: AppIdentity, home: String) -> Set<URL> {
        let homeURL = NormalizedPath.url(home, isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: homeURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return [] }

        var found = Set<URL>()
        for item in contents {
            let name = item.lastPathComponent
            if Self.homeResidualDenyList.contains(name) { continue }
            let lower = name.lowercased()
            let bare = lower.hasPrefix(".") ? String(lower.dropFirst()) : lower
            guard bare.count >= 3 else { continue }

            let appHit = EvidenceProbe.appNameMatchesFileName(name, appName: identity.appName)
            var matched = appHit.exact || appHit.prefix
            if !matched, let bundleName = identity.bundleName, !bundleName.isEmpty {
                let bundleHit = EvidenceProbe.appNameMatchesFileName(name, appName: bundleName)
                matched = bundleHit.exact || bundleHit.prefix
            }
            if !matched {
                let exec = identity.executableName.lowercased()
                if exec.count >= 3 {
                    matched = bare == exec
                        || lower == ".\(exec)"
                        || bare.hasPrefix(exec + "-")
                        || bare.hasPrefix(exec + "_")
                }
            }
            if matched {
                found.insert(NormalizedPath.canonicalize(item))
            }
        }
        return NormalizedPath.urls(found)
    }

    /// Debug / CI `.app` bundles under /private/tmp (balanced only).
    private func collectTmpAppBundles(identity: AppIdentity) async -> Set<URL> {
        let targetApp = identity.bundleURL.lastPathComponent.lowercased()
        let appName = identity.appName.lowercased()
        guard targetApp.hasSuffix(".app") || appName.count >= 3 else { return [] }
        return await scanTmpDir(tmpScanDirectory, targetApp: targetApp, appName: appName, depth: 0, maxDepth: 5)
    }

    private func scanTmpDir(
        _ url: URL,
        targetApp: String,
        appName: String,
        depth: Int,
        maxDepth: Int
    ) async -> Set<URL> {
        guard depth <= maxDepth else { return [] }
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return found }

        for item in contents {
            let lower = item.lastPathComponent.lowercased()
            if lower == targetApp {
                found.insert(NormalizedPath.canonicalize(item))
                continue
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            if appName.count >= 4, lower.contains(appName) {
                // Descend into name-matching project folders (e.g. MacOSCleaner-Polish/…).
                found.formUnion(
                    await scanTmpDir(item, targetApp: targetApp, appName: appName, depth: depth + 1, maxDepth: maxDepth)
                )
            } else if depth < maxDepth {
                // Shallow walk only a couple levels for Build/Products/Debug layouts.
                if lower == "build" || lower == "products" || lower == "debug" || lower == "release" {
                    found.formUnion(
                        await scanTmpDir(item, targetApp: targetApp, appName: appName, depth: depth + 1, maxDepth: maxDepth)
                    )
                }
            }
        }
        return found
    }

    /// Bundle IDs excluded from registry lookup (SIP system apps).
    private static let registryExcludedBundleIDs: Set<String> = ["com.apple.safari"]

    private struct RegistryCollectionResult: Sendable {
        var candidates: Set<URL> = []
        var catalogPaths: Set<URL> = []
        var sharedPaths: Set<URL> = []
        var informationalPaths: Set<URL> = []
    }

    private func collectRegistryPaths(identity: AppIdentity, home: String) -> RegistryCollectionResult {
        let bundleID = identity.bundleID.lowercased()
        guard !bundleID.isEmpty, !bundleID.hasPrefix("unknown."),
              !Self.registryExcludedBundleIDs.contains(bundleID),
              let appPaths = GeneratedCleanupPaths.appPaths(forBundleID: identity.bundleID)
        else {
            return RegistryCollectionResult()
        }

        var result = RegistryCollectionResult()
        var catalogEligible = Set<URL>()

        for entry in appPaths.paths {
            for path in expandRegistryPath(entry, home: home) {
                let url = NormalizedPath.url(path)
                switch entry.purpose {
                case .shared:
                    result.sharedPaths.insert(url)
                case .userContent:
                    result.informationalPaths.insert(url)
                case .cache, .appData:
                    guard !entry.requiresAdmin else { continue }
                    result.candidates.insert(url)
                    if entry.purpose == .cache {
                        catalogEligible.insert(url)
                    }
                }
            }
        }

        result.catalogPaths = Self.excludingAncestorPaths(catalogEligible)
        return result
    }

    private func expandRegistryPath(_ entry: RegistryPath, home: String) -> [String] {
        let resolved = PathToken.home.resolveTemplate(entry.template, home: home)
        return CleanupPathExpander.expand(resolved, home: home, fileManager: fileManager)
    }

    /// Drops catalog paths that are strict ancestors of another catalog path.
    private static func excludingAncestorPaths(_ paths: Set<URL>) -> Set<URL> {
        let normalized = Array(NormalizedPath.urls(paths))
        return Set(normalized.filter { candidate in
            let path = NormalizedPath.key(candidate)
            return !normalized.contains { other in
                let otherPath = NormalizedPath.key(other)
                return otherPath != path && otherPath.hasPrefix(path + "/")
            }
        })
    }

    private func collectFromLSRegister(identity: AppIdentity) async -> Set<URL> {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        guard fileManager.fileExists(atPath: lsregister),
              let result = try? await commandRunner.run(command: lsregister, arguments: ["-dump"]) else { return [] }

        let bundleIDLower = identity.bundleID.lowercased()
        var found = Set<URL>()
        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("path:") else { continue }
            let path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard path.lowercased().contains(bundleIDLower) else { continue }
            found.insert(NormalizedPath.url(path))
        }
        return found
    }

    /// Sibling `.app` bundles in configured Homebrew Cellar directories that share
    /// the same bundle name. Returned as candidates only — never receiptPaths.
    private func collectHomebrewSiblingApps(identity: AppIdentity) -> Set<URL> {
        guard !homebrewCellarDirectories.isEmpty else { return [] }
        let targetName = identity.bundleURL.lastPathComponent.lowercased()
        guard targetName.hasSuffix(".app") else { return [] }

        var found = Set<URL>()
        for cellar in homebrewCellarDirectories {
            guard let formulae = try? fileManager.contentsOfDirectory(
                at: cellar,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for formula in formulae {
                guard let versions = try? fileManager.contentsOfDirectory(
                    at: formula,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for version in versions {
                    guard let apps = try? fileManager.contentsOfDirectory(
                        at: version,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for app in apps where app.lastPathComponent.lowercased() == targetName {
                        let resolved = app.resolvingSymlinksInPath()
                        if let bundleID = Bundle(url: resolved)?.bundleIdentifier?.lowercased(),
                           !bundleID.isEmpty,
                           bundleID != identity.bundleID.lowercased() {
                            continue
                        }
                        found.insert(resolved)
                    }
                }
            }
        }
        return found
    }

    /// Files recorded in installer receipts for packages whose id matches the bundle ID.
    /// Paths inside the app bundle are skipped — the bundle is removed as a whole anyway.
    private func collectPkgutilReceiptPaths(identity: AppIdentity) async -> Set<URL> {
        guard !identity.bundleID.isEmpty, !identity.bundleID.hasPrefix("unknown.") else { return [] }

        var packageIDs: Set<String> = [identity.bundleID]
        if let result = try? await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--pkgs"]) {
            for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
                if line == identity.bundleID || line.hasPrefix(identity.bundleID + ".") {
                    packageIDs.insert(line)
                }
            }
        }

        var found = Set<URL>()
        let bundlePrefix = identity.bundleURL.standardizedFileURL.path + "/"
        for packageID in packageIDs {
            guard let result = try? await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--files", packageID]),
                  result.exitCode == 0 else { continue }
            for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
                let path = NormalizedPath.join("/", line)
                guard !path.hasPrefix(bundlePrefix), fileManager.fileExists(atPath: path) else { continue }
                found.insert(NormalizedPath.url(path))
            }
        }
        return found
    }

    private func shallowScan(_ url: URL, identity: AppIdentity, mode: ScanMode = .balanced) async -> Set<URL> {
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            if matchCandidate(item, identity: identity, mode: mode) {
                found.insert(NormalizedPath.canonicalize(item))
            }
        }
        return found
    }

    private func deepScan(
        _ url: URL,
        identity: AppIdentity,
        depth: Int,
        maxDepth: Int,
        mode: ScanMode,
        insideMatch: Bool = false
    ) async -> Set<URL> {
        guard depth <= maxDepth else { return [] }
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            let matched = matchCandidate(item, identity: identity, mode: mode)
            if matched {
                found.insert(NormalizedPath.canonicalize(item))
            }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                // Walk matched trees fully; for unmatched siblings only descend vendor hubs
                // (Google/) so we don't traverse Chrome profiles while scanning Studio.
                let descend = matched
                    || insideMatch
                    || Self.shouldDescendForResidualScan(item, identity: identity)
                guard descend else { continue }
                let sub = await deepScan(
                    item,
                    identity: identity,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    mode: mode,
                    insideMatch: matched || insideMatch
                )
                found.formUnion(sub)
            }
        }
        return found
    }

    /// Vendor / mega-vendor folders that host per-product children (Google/AndroidStudio…).
    private static func shouldDescendForResidualScan(_ url: URL, identity: AppIdentity) -> Bool {
        let name = url.lastPathComponent
        if identity.vendorNames.contains(name) { return true }
        if sharedMegaVendors.contains(name) { return true }
        return false
    }

    private func matchCandidate(_ url: URL, identity: AppIdentity, mode: ScanMode = .balanced) -> Bool {
        if Self.isForeignDeveloperTree(url, identity: identity) {
            return false
        }
        if Self.isForeignAppLibraryTree(url, identity: identity) {
            return false
        }
        let name = url.lastPathComponent
        let lowerName = name.lowercased()
        let lowerBundleID = identity.bundleID.lowercased()
        let lowerAppName = identity.appName.lowercased()
        let lowerExecutable = identity.executableName.lowercased()
        let lowerBundleName = identity.bundleName?.lowercased()

        // Exact matches — always checked. Case-insensitive: Electron apps often use
        // lowercase data dirs (~/Library/Application Support/discord for "Discord").
        if lowerName == lowerBundleID || lowerName.hasPrefix(lowerBundleID + ".") {
            return true
        }
        let appHit = EvidenceProbe.appNameMatchesFileName(name, appName: identity.appName)
        if appHit.exact {
            return true
        }
        if appHit.prefix, !Self.looksLikeSourceFile(lowerName) {
            // Prefer residual suffixes for dotted names; compact IDE dirs OK (AndroidStudio2026).
            let bare = lowerName.hasPrefix(".") ? String(lowerName.dropFirst()) : lowerName
            let isDottedResidual = bare.contains(".")
            if !isDottedResidual || Self.matchesAppNameResidualSuffix(lowerName, appToken: lowerAppName) {
                return true
            }
            // Compact prefix without spaces: AndroidStudio2026.1.2
            let cFile = EvidenceProbe.compactIdentityToken(bare)
            let cApp = EvidenceProbe.compactIdentityToken(lowerAppName)
            if cApp.count >= 5, cFile.hasPrefix(cApp) {
                return true
            }
        }
        if let bundleName = identity.bundleName, !bundleName.isEmpty {
            let bundleHit = EvidenceProbe.appNameMatchesFileName(name, appName: bundleName)
            if bundleHit.exact { return true }
            if bundleHit.prefix, !Self.looksLikeSourceFile(lowerName) {
                let cFile = EvidenceProbe.compactIdentityToken(lowerName)
                let cBundle = EvidenceProbe.compactIdentityToken(bundleName)
                if cBundle.count >= 5, cFile.hasPrefix(cBundle) { return true }
                if Self.matchesAppNameResidualSuffix(lowerName, appToken: bundleName.lowercased()) {
                    return true
                }
            }
        }
        // TeamID containers: require declared app group or product-suffix match.
        // Bare TeamID. prefix alone cross-selects Office siblings (Excel ↔ Word widgets).
        if let teamID = identity.teamID, !teamID.isEmpty, name.hasPrefix(teamID + ".") {
            if identity.appGroups.contains(name) { return true }
            let suffix = String(name.dropFirst(teamID.count + 1)).lowercased()
            if EvidenceProbe.bundleIDSuffixMatch(suffix, bundleID: lowerBundleID) { return true }
            if !lowerAppName.isEmpty, EvidenceProbe.tokenPrefixMatch(suffix, lowerAppName) { return true }
        }
        // App groups declared in the signature entitlements (TC3Q7MAJXF.com.adguard.mac)
        if identity.appGroups.contains(name) {
            return true
        }
        // Embedded helper / framework names (Electron Helper, privhelper binaries).
        for helper in identity.helperNames {
            let helperLower = helper.lowercased()
            guard helperLower.count >= 3 else { continue }
            if lowerName == helperLower || lowerName.hasPrefix(helperLower + ".") {
                return true
            }
        }
        // Bundle ID tail inside a vendor folder: Google/Chrome from com.google.Chrome.
        // Without the vendor-parent guard a generic tail ("desktop" from
        // ai.opencode.desktop) matches Data/Desktop in every sandbox container.
        if let tail = lowerBundleID.split(separator: ".").last.map(String.init), tail.count >= 3 {
            let parentName = url.deletingLastPathComponent().lastPathComponent.lowercased()
            let parentIsVendor = identity.vendorNames.contains { $0.lowercased() == parentName }
            if parentIsVendor,
               lowerName == tail || lowerName.hasPrefix(tail + "-") || lowerName.hasPrefix(tail + "_") {
                return true
            }
        }
        // Token prefix: opencode-desktop_br for OpenCode (dirs / residual names only).
        if !Self.looksLikeSourceFile(lowerName) {
            if EvidenceProbe.tokenPrefixMatch(lowerName, lowerAppName) { return true }
            if EvidenceProbe.tokenPrefixMatch(lowerName, lowerExecutable) { return true }
            if let lowerBundleName, EvidenceProbe.tokenPrefixMatch(lowerName, lowerBundleName) { return true }
        }

        // Safe mode: only exact matches above
        if mode == .safe { return false }

        // Balanced: product-specific vendor dirs only — never bare Google/Microsoft/Adobe
        // roots that host many apps (Chrome + Android Studio + Drive share ~/Library/.../Google).
        if identity.vendorNames.contains(name), !Self.sharedMegaVendors.contains(name) {
            return true
        }
        if lowerName.contains(lowerBundleID) {
            return true
        }
        // Whole-token app name in directory names; never substring inside Cursor.java etc.
        if !Self.looksLikeSourceFile(lowerName),
           EvidenceProbe.wordBoundaryMatch(lowerName, lowerAppName) {
            return true
        }
        if lowerName == lowerExecutable {
            return true
        }

        return false
    }

    /// Shared vendor folder names that must not match as residuals by themselves.
    private static let sharedMegaVendors: Set<String> = [
        "Google", "Microsoft", "Adobe", "Oracle", "Apple",
    ]

    private static let residualNameSuffixes: Set<String> = [
        "plist", "sfl", "sfl2", "sfl3", "sfl4", "savedstate",
        "shipit", "helper", "binarycookies", "gpu",
    ]

    private static let sourceFileExtensions: Set<String> = [
        "java", "swift", "m", "mm", "h", "hpp", "c", "cpp", "cc",
        "js", "jsx", "ts", "tsx", "py", "rb", "go", "kt", "kts",
        "rs", "cs", "scala", "groovy", "dart",
    ]

    private static func looksLikeSourceFile(_ lowerName: String) -> Bool {
        guard lowerName.contains("."), !lowerName.hasPrefix(".") else { return false }
        return sourceFileExtensions.contains((lowerName as NSString).pathExtension)
    }

    /// `App.plist` / `App.ShipIt` / `App.helper` — not `App.java`.
    private static func matchesAppNameResidualSuffix(_ lowerName: String, appToken: String) -> Bool {
        guard !appToken.isEmpty, lowerName.hasPrefix(appToken + ".") else { return false }
        let rest = String(lowerName.dropFirst(appToken.count + 1))
        if looksLikeSourceFile(lowerName) { return false }
        return residualNameSuffixes.contains { suffix in
            rest == suffix || rest.hasPrefix(suffix + ".") || rest.hasPrefix(suffix + "-")
        }
    }

    /// Cross-IDE trees that share generic names (e.g. Xcode.rst inside Android SDK).
    static func isForeignDeveloperTree(_ url: URL, identity: AppIdentity) -> Bool {
        let path = url.standardizedFileURL.path.lowercased()
        let bid = identity.bundleID.lowercased()
        let name = identity.appName.lowercased()

        let isXcode = bid == "com.apple.dt.xcode" || (name == "xcode" && bid.hasPrefix("com.apple.dt"))
        if isXcode {
            if path.contains("/library/android") { return true }
            if path.contains("/.gradle") || path.hasSuffix("/.gradle") { return true }
            if path.contains("/.android") || path.hasSuffix("/.android") { return true }
            return false
        }

        let isAndroidStudio = bid.contains("android.studio") || name.contains("android studio")
        if isAndroidStudio {
            if path.contains("/library/developer/xcode") { return true }
            if path.contains("/library/developer/coresimulator") { return true }
            return false
        }

        // Cursor / IDEs must not claim Android SDK sources (Cursor.java, etc.).
        if path.contains("/library/android/") || path.contains("/.android/") || path.hasSuffix("/.android") {
            return true
        }
        return false
    }

    /// Another app's Library subtree (e.g. Nektony updater cache holding OpenCode metadata).
    static func isForeignAppLibraryTree(_ url: URL, identity: AppIdentity) -> Bool {
        let path = url.standardizedFileURL.path.lowercased()
        let bid = identity.bundleID.lowercased()
        guard !bid.isEmpty, !bid.hasPrefix("unknown.") else { return false }

        let folders = [
            "/library/caches/",
            "/library/application support/",
            "/library/httpstorages/",
            "/library/preferences/",
            "/library/containers/",
            "/library/logs/",
        ]
        for folder in folders {
            guard let range = path.range(of: folder) else { continue }
            var foreign = String(path[range.upperBound...].prefix(while: { $0 != "/" }))
            if foreign.hasSuffix(".plist") {
                foreign = String(foreign.dropLast(6))
            }
            // Only reverse-DNS style library buckets.
            let looksLikeBundle = foreign.contains(".") && (
                foreign.hasPrefix("com.") || foreign.hasPrefix("org.") || foreign.hasPrefix("net.")
                    || foreign.hasPrefix("io.") || foreign.hasPrefix("ai.") || foreign.hasPrefix("dev.")
                    || foreign.hasPrefix("app.") || foreign.hasPrefix("co.")
            )
            guard looksLikeBundle else { continue }
            // System holders that store per-app children by our bundle ID / name.
            if foreign.hasPrefix("com.apple.") { continue }
            if foreign == bid || foreign.hasPrefix(bid + ".") { continue }
            if bid.hasPrefix(foreign + ".") { continue }
            return true
        }
        return false
    }

    // MARK: - Browser vendor paths

    /// Google Chrome lives under ~/Library/.../Google/Chrome, not a top-level "Google Chrome" folder.
    private func collectBrowserVendorPaths(identity: AppIdentity, home: String, maxDepth: Int) async -> Set<URL> {
        let bid = identity.bundleID.lowercased()
        let app = identity.appName.lowercased()
        var vendorRoots: [(vendor: String, product: String?)] = []

        if bid.contains("google") && (bid.contains("chrome") || app.contains("chrome")) {
            vendorRoots.append(("Google", "Chrome"))
        } else if bid.contains("mozilla") || app.contains("firefox") {
            vendorRoots.append(("Mozilla", nil))
            vendorRoots.append(("Firefox", nil))
        } else if bid.contains("microsoft.edgemac") || app.contains("edge") {
            vendorRoots.append(("Microsoft Edge", nil))
        } else if bid.contains("brave") || app.contains("brave") {
            vendorRoots.append(("BraveSoftware", nil))
            vendorRoots.append(("BraveSoftware", "Brave-Browser"))
        } else if bid.contains("operasoftware") || app.contains("opera") {
            vendorRoots.append(("com.operasoftware.Opera", nil))
            vendorRoots.append(("Opera Software", nil))
            vendorRoots.append(("Opera", nil))
        } else if bid.contains("vivaldi") || app.contains("vivaldi") {
            vendorRoots.append(("Vivaldi", nil))
        } else if bid.contains("thebrowser") || app == "arc" {
            vendorRoots.append(("Arc", nil))
        } else if bid.contains("chromium") || app.contains("chromium") {
            vendorRoots.append(("Chromium", nil))
        } else if bid.contains("torproject") || app.contains("tor") {
            vendorRoots.append(("TorBrowser-Data", nil))
        } else if bid.contains("duckduckgo") {
            vendorRoots.append(("DuckDuckGo", nil))
        } else if bid.contains("yandex") {
            vendorRoots.append(("Yandex", nil))
        }

        var found = Set<URL>()
        let nestedBases = [
            NormalizedPath.joinHome(home, "Library/Application Support"),
            NormalizedPath.joinHome(home, "Library/Caches"),
            NormalizedPath.joinHome(home, "Library/Logs"),
        ]
        for (vendor, product) in vendorRoots {
            for base in nestedBases {
                let vendorURL = NormalizedPath.url(base, isDirectory: true).appendingPathComponent(vendor)
                guard fileManager.fileExists(atPath: vendorURL.path) else { continue }
                if let product {
                    let productURL = vendorURL.appendingPathComponent(product)
                    if fileManager.fileExists(atPath: productURL.path) {
                        found.insert(NormalizedPath.canonicalize(productURL))
                        found.formUnion(await deepScan(productURL, identity: identity, depth: 0, maxDepth: maxDepth, mode: .balanced))
                    }
                } else {
                    found.insert(NormalizedPath.canonicalize(vendorURL))
                    found.formUnion(await deepScan(vendorURL, identity: identity, depth: 0, maxDepth: maxDepth, mode: .balanced))
                }
            }
            // ~/Library/{Vendor} — e.g. GoogleSoftwareUpdate / Keystone beside Application Support.
            let libraryVendor = NormalizedPath.url(NormalizedPath.joinHome(home, "Library"), isDirectory: true)
                .appendingPathComponent(vendor)
            if fileManager.fileExists(atPath: libraryVendor.path) {
                found.insert(NormalizedPath.canonicalize(libraryVendor))
                found.formUnion(
                    await deepScan(libraryVendor, identity: identity, depth: 0, maxDepth: min(maxDepth, 3), mode: .balanced)
                )
            }
        }
        return found
    }

    // MARK: - VM user data outside ~/Library

    private func isVirtualizationApp(_ identity: AppIdentity) -> Bool {
        if identity.isDocker { return true }
        let bid = identity.bundleID.lowercased()
        let name = identity.appName.lowercased()
        let markers = ["parallels", "vmware", "virtualbox", "utm", "orbstack", "qemu"]
        return markers.contains { bid.contains($0) || name.contains($0) }
    }

    private func vmDataTokens(for identity: AppIdentity) -> [String] {
        var tokens = Set<String>()
        let bid = identity.bundleID.lowercased()
        let name = identity.appName.lowercased()
        if bid.contains("orbstack") || name.contains("orbstack") {
            tokens.formUnion(["orbstack", "orbstack_files", "orbstack files"])
        }
        if bid.contains("parallels") || name.contains("parallels") {
            tokens.formUnion(["parallels"])
        }
        if bid.contains("vmware") || name.contains("vmware") {
            tokens.formUnion(["vmware", "virtual machines"])
        }
        if bid.contains("virtualbox") || name.contains("virtualbox") {
            tokens.formUnion(["virtualbox", "virtualbox vms"])
        }
        if bid.contains("utm") || name == "utm" {
            tokens.formUnion(["utm"])
        }
        if bid.contains("docker") || name.contains("docker") {
            tokens.formUnion(["docker"])
        }
        return Array(tokens)
    }

    private func scanVMUserData(identity: AppIdentity) async -> Set<URL> {
        let tokens = vmDataTokens(for: identity)
        guard !tokens.isEmpty else { return [] }
        var found = Set<URL>()
        let roots = ["/Users/Shared"]
        for root in roots {
            let url = NormalizedPath.url(root, isDirectory: true)
            found.formUnion(await scanVMDataDir(url, tokens: tokens, depth: 0, maxDepth: 5))
        }
        return found
    }

    private func scanVMDataDir(_ url: URL, tokens: [String], depth: Int, maxDepth: Int) async -> Set<URL> {
        guard depth <= maxDepth else { return [] }
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            let lower = item.lastPathComponent.lowercased()
            if tokens.contains(where: { lower.contains($0) }) {
                found.insert(item)
            }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                found.formUnion(await scanVMDataDir(item, tokens: tokens, depth: depth + 1, maxDepth: maxDepth))
            }
        }
        return found
    }

    /// Attribute-scoped Spotlight lookup. Raw text queries are forbidden here: they run a
    /// full-content search and match user documents/mail that merely mention the app name.
    private func runMdfind(identity: AppIdentity) async -> Set<URL> {
        var queries: [(query: String, onlyIn: String?)] = []

        if !identity.bundleID.isEmpty, !identity.bundleID.hasPrefix("unknown.") {
            // Bundles carrying the app's identifier (stray copies, helpers) — precise, safe globally
            queries.append(("kMDItemCFBundleIdentifier == '\(mdfindEscape(identity.bundleID))'", nil))
        }

        // Name lookups are fuzzy — restrict to ~/Library where residuals actually live
        let home = fileSystemContext.homePath
        let names = Set([identity.appName, identity.executableName].filter { !$0.isEmpty })
        for name in names {
            queries.append(("kMDItemFSName == '\(mdfindEscape(name))*'cd", NormalizedPath.joinHome(home, "Library")))
        }

        var urls = Set<URL>()
        for (query, onlyIn) in queries {
            var arguments: [String] = []
            if let onlyIn { arguments += ["-onlyin", onlyIn] }
            arguments.append(query)
            if let result = try? await commandRunner.run(command: "/usr/bin/mdfind", arguments: arguments) {
                for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
                    urls.insert(NormalizedPath.url(line))
                }
            }
        }
        return urls
    }

    private func mdfindEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
