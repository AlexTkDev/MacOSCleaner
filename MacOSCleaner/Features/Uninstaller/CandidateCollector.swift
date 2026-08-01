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
    private let darwinCacheDirectory: URL
    private let fileSystemContext: FileSystemContext

    public init(
        fileManager: FileManager = .default,
        commandRunner: any CommandRunning = CommandRunner(),
        homebrewCellarDirectories: [URL] = AppDiscovery.defaultHomebrewCellarDirectories,
        darwinCacheDirectory: URL? = nil,
        fileSystemContext: FileSystemContext = .production
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.homebrewCellarDirectories = homebrewCellarDirectories
        self.fileSystemContext = fileSystemContext
        let cacheDirectory = darwinCacheDirectory
            ?? fileManager.temporaryDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("C", isDirectory: true)
        self.darwinCacheDirectory = cacheDirectory.resolvingSymlinksInPath()
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
        ]

        for base in basePaths {
            let url = NormalizedPath.url(base, isDirectory: true)
            candidates.formUnion(await shallowScan(url, identity: identity, mode: mode))
        }

        // Current user's Darwin cache root (/private/var/folders/.../C).
        // Exact bundle-ID prefixes find helper caches without scanning other users,
        // temp files, or generic vendor names.
        candidates.formUnion(collectDarwinCachePaths(identity: identity))

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
        // (other versions must stay unselected for delete).
        let homebrewSiblings = collectHomebrewSiblingApps(identity: identity)
        candidates.formUnion(homebrewSiblings)

        // 4. mdfind (balanced only)
        if mode == .balanced {
            let mdfindCandidates = await runMdfind(identity: identity)
            candidates.formUnion(mdfindCandidates)
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

        // 7. Docker-specific
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
        candidates.subtract(registry.sharedPaths)
        candidates.subtract(registry.informationalPaths)

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

    private func collectDarwinCachePaths(identity: AppIdentity) -> Set<URL> {
        let bundleID = identity.bundleID.lowercased()
        guard !bundleID.isEmpty, !bundleID.hasPrefix("unknown."),
              let contents = try? fileManager.contentsOfDirectory(
                at: darwinCacheDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        return Set(contents.filter {
            let name = $0.lastPathComponent.lowercased()
            return name == bundleID || name.hasPrefix(bundleID + ".")
        })
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
        let normalized = paths.map { $0.standardizedFileURL }
        return Set(normalized.filter { candidate in
            let path = candidate.path
            return !normalized.contains { other in
                other.path != path && other.path.hasPrefix(path + "/")
            }
        })
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
                found.insert(item)
            }
        }
        return found
    }

    private func deepScan(_ url: URL, identity: AppIdentity, depth: Int, maxDepth: Int, mode: ScanMode) async -> Set<URL> {
        guard depth <= maxDepth else { return [] }
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            if matchCandidate(item, identity: identity, mode: mode) {
                found.insert(item)
            }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let sub = await deepScan(item, identity: identity, depth: depth + 1, maxDepth: maxDepth, mode: mode)
                found.formUnion(sub)
            }
        }
        return found
    }

    private func matchCandidate(_ url: URL, identity: AppIdentity, mode: ScanMode = .balanced) -> Bool {
        if Self.isForeignDeveloperTree(url, identity: identity) {
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
        if lowerName == lowerAppName
            || lowerName.hasPrefix(lowerAppName + " ")
            || lowerName.hasPrefix(lowerAppName + ".")
            || lowerName.hasPrefix(lowerAppName + "-") {
            return true
        }
        if let lowerBundleName, !lowerBundleName.isEmpty,
           (lowerName == lowerBundleName
            || lowerName.hasPrefix(lowerBundleName + " ")
            || lowerName.hasPrefix(lowerBundleName + "-")) {
            return true
        }
        // TeamID-prefixed containers (e.g. Group Containers/UBF8T346G9.Office)
        if let teamID = identity.teamID, !teamID.isEmpty, name.hasPrefix(teamID + ".") {
            return true
        }
        // App groups declared in the signature entitlements (TC3Q7MAJXF.com.adguard.mac)
        if identity.appGroups.contains(name) {
            return true
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
        // Token prefix: opencode-desktop_br for OpenCode
        if EvidenceProbe.tokenPrefixMatch(lowerName, lowerAppName) { return true }
        if EvidenceProbe.tokenPrefixMatch(lowerName, lowerExecutable) { return true }
        if let lowerBundleName { if EvidenceProbe.tokenPrefixMatch(lowerName, lowerBundleName) { return true } }

        // Safe mode: only exact matches above
        if mode == .safe { return false }

        // Balanced: exact vendor directory name only (e.g. "Adobe").
        // Do NOT match "Microsoft Excel" via contains("Microsoft") — that cross-selects siblings.
        if identity.vendorNames.contains(name) {
            return true
        }
        if lowerName.contains(lowerBundleID) {
            return true
        }
        if lowerName.contains(lowerAppName) {
            return true
        }
        if lowerName == lowerExecutable {
            return true
        }

        return false
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
        let bases = [
            NormalizedPath.joinHome(home, "Library/Application Support"),
            NormalizedPath.joinHome(home, "Library/Caches"),
            NormalizedPath.joinHome(home, "Library/Logs"),
        ]
        for (vendor, product) in vendorRoots {
            for base in bases {
                let vendorURL = NormalizedPath.url(base, isDirectory: true).appendingPathComponent(vendor)
                guard fileManager.fileExists(atPath: vendorURL.path) else { continue }
                if let product {
                    let productURL = vendorURL.appendingPathComponent(product)
                    if fileManager.fileExists(atPath: productURL.path) {
                        found.insert(productURL)
                        found.formUnion(await deepScan(productURL, identity: identity, depth: 0, maxDepth: maxDepth, mode: .balanced))
                    }
                } else {
                    found.insert(vendorURL)
                    found.formUnion(await deepScan(vendorURL, identity: identity, depth: 0, maxDepth: maxDepth, mode: .balanced))
                }
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
