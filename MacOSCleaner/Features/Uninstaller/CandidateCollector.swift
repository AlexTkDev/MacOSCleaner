import Foundation

public struct CandidateCollection: Sendable {
    public let candidates: Set<URL>
    /// Subset of `candidates` owned by a package-manager receipt — guaranteed app files.
    public let receiptPaths: Set<URL>
    /// Subset from KnownResidualCatalog — high-confidence curated residuals.
    public let catalogPaths: Set<URL>
}

public actor CandidateCollector {
    private let fileManager: FileManager
    private let commandRunner: any CommandRunning
    private let homebrewCellarDirectories: [URL]
    private let darwinCacheDirectory: URL

    public init(
        fileManager: FileManager = .default,
        commandRunner: any CommandRunning = CommandRunner(),
        homebrewCellarDirectories: [URL] = AppDiscovery.defaultHomebrewCellarDirectories,
        darwinCacheDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.homebrewCellarDirectories = homebrewCellarDirectories
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
        let home = NSHomeDirectory()
        let maxDepth = mode == .safe ? 3 : 5

        // 1. Fixed popular paths
        let basePaths = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Preferences",
            "\(home)/Library/Preferences/ByHost",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Logs",
            "\(home)/Library/Logs/DiagnosticReports",
            "\(home)/Library/Cookies",
            "\(home)/Library/Internet Plug-Ins",
            "\(home)/Library/QuickLook",
            "\(home)/Library/Application Support/CrashReporter",
            "\(home)/Library/LaunchAgents",
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
            "\(home)/Library/Developer",
        ]

        for base in basePaths {
            let url = URL(fileURLWithPath: base)
            candidates.formUnion(await shallowScan(url, identity: identity, mode: mode))
        }

        // Current user's Darwin cache root (/private/var/folders/.../C).
        // Exact bundle-ID prefixes find helper caches without scanning other users,
        // temp files, or generic vendor names.
        candidates.formUnion(collectDarwinCachePaths(identity: identity))

        // 2. Deep scan critical folders
        let deepFolders = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Preferences",
            "\(home)/Library/Application Scripts",
        ]
        for dir in deepFolders {
            let url = URL(fileURLWithPath: dir)
            candidates.formUnion(await deepScan(url, identity: identity, depth: 0, maxDepth: maxDepth))
        }

        // 3. Package-manager receipts. Homebrew can keep the same app bundle in
        // several versioned formulae (python@3.12 and python@3.14).
        var receiptPaths = await collectPkgutilReceiptPaths(identity: identity)
        let homebrewApplications = AppDiscovery.homebrewFormulaApplications(
            containing: identity.bundleURL,
            cellarDirectories: homebrewCellarDirectories,
            fileManager: fileManager
        )
        receiptPaths.formUnion(homebrewApplications.filter {
            Bundle(url: $0)?.bundleIdentifier?.caseInsensitiveCompare(identity.bundleID) == .orderedSame
        })
        candidates.formUnion(receiptPaths)

        // 4. mdfind (balanced only)
        if mode == .balanced {
            let mdfindCandidates = await runMdfind(identity: identity)
            candidates.formUnion(mdfindCandidates)
        }

        // 5. App-specific Electron paths
        if identity.isElectron {
            let electronPath = "\(home)/Library/Application Support/\(identity.appName)"
            if fileManager.fileExists(atPath: electronPath) {
                candidates.insert(URL(fileURLWithPath: electronPath))
            }
        }

        // 6. JetBrains-specific (balanced only)
        if mode == .balanced, identity.isJetBrains {
            let jbPath = "\(home)/Library/Application Support/JetBrains"
            if fileManager.fileExists(atPath: jbPath) {
                candidates.formUnion(await shallowScan(URL(fileURLWithPath: jbPath), identity: identity, mode: mode))
                candidates.formUnion(await deepScan(URL(fileURLWithPath: jbPath), identity: identity, depth: 0, maxDepth: maxDepth))
            }
        }

        // 7. Docker-specific
        if identity.isDocker {
            let dockerPaths = [
                "\(home)/Library/Containers/com.docker.docker",
                "\(home)/Library/Group Containers/group.com.docker",
            ]
            for p in dockerPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 8. Adobe-specific
        let adobeVendor = identity.appName.lowercased().hasPrefix("adobe") ||
            identity.bundleID.lowercased().hasPrefix("com.adobe.")
        if adobeVendor {
            let adobePaths = [
                "\(home)/Library/Application Support/Adobe",
                "/Library/Application Support/Adobe",
                "\(home)/Library/Preferences/Adobe",
                "/Library/Preferences/Adobe",
                "\(home)/.adobe",
                "\(home)/Creative Cloud Files",
            ]
            for p in adobePaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 9. Microsoft Office-specific
        let msVendor = identity.appName.lowercased().hasPrefix("microsoft") ||
            identity.bundleID.lowercased().hasPrefix("com.microsoft.")
        if msVendor {
            let msPaths = [
                "\(home)/Library/Application Support/Microsoft",
                "\(home)/Library/Application Support/Microsoft Office",
                "\(home)/Library/Group Containers/UBF8T346G9.Office",
                "\(home)/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite",
                "/Library/Application Support/Microsoft",
                "\(home)/Library/Containers/com.microsoft.word",
                "\(home)/Library/Containers/com.microsoft.excel",
                "\(home)/Library/Containers/com.microsoft.powerpoint",
                "\(home)/Library/Containers/com.microsoft.outlook",
                "\(home)/Library/Containers/com.microsoft.teams",
            ]
            for p in msPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 10. Steam-specific
        if identity.bundleID == "com.valvesoftware.steam" || identity.appName == "Steam" {
            let steamPaths = [
                "\(home)/Library/Application Support/Steam",
            ]
            for p in steamPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 11. Epic Games-specific
        if identity.bundleID == "com.epicgames.EpicGamesLauncher" || identity.appName.lowercased().contains("epic") {
            let epicPaths = [
                "\(home)/Library/Application Support/Epic",
                "\(home)/Library/Application Support/Epic Games Launcher",
            ]
            for p in epicPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 12. Unity-specific
        if identity.bundleID.lowercased().hasPrefix("com.unity3d.") || identity.appName == "Unity Hub" {
            let unityPaths = [
                "\(home)/Library/Application Support/Unity",
                "\(home)/Library/Application Support/Unity Hub",
                "\(home)/.local/share/unity3d",
            ]
            for p in unityPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 13. Network extension / VPN-specific
        let isNetworkExt = identity.bundleID.lowercased().contains("littlesnitch") ||
            identity.bundleID.lowercased().contains("nordvpn") ||
            identity.bundleID.lowercased().contains("expressvpn") ||
            identity.appName.lowercased().contains("vpn") ||
            identity.appName.lowercased().contains("snitch")
        if isNetworkExt {
            let nePaths = [
                "/Library/SystemExtensions",
                "/Library/StagedExtensions",
                "\(home)/Library/Application Support/Little Snitch",
                "\(home)/Library/Application Support/NordVPN",
            ]
            for p in nePaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 14. VM / container user data outside ~/Library (OrbStack_files, Parallels, …)
        if isVirtualizationApp(identity) {
            candidates.formUnion(await scanVMUserData(identity: identity, home: home))
        }

        // 15. Browser vendor folders (Google/Chrome, Mozilla/Firefox, …)
        candidates.formUnion(await collectBrowserVendorPaths(identity: identity, home: home, maxDepth: maxDepth))

        // 16. Known residual catalog (exact/glob templates for problematic apps)
        let catalogPaths = collectCatalogPaths(identity: identity, home: home)
        candidates.formUnion(catalogPaths)

        return CandidateCollection(candidates: candidates, receiptPaths: receiptPaths, catalogPaths: catalogPaths)
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

    private func collectCatalogPaths(identity: AppIdentity, home: String) -> Set<URL> {
        var found = Set<URL>()
        for template in KnownResidualCatalog.pathTemplates(for: identity) {
            for path in KnownResidualCatalog.expand(template: template, home: home, fileManager: fileManager) {
                found.insert(URL(fileURLWithPath: path))
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
                let path = "/\(line)"
                guard !path.hasPrefix(bundlePrefix), fileManager.fileExists(atPath: path) else { continue }
                found.insert(URL(fileURLWithPath: path))
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

    private func deepScan(_ url: URL, identity: AppIdentity, depth: Int, maxDepth: Int) async -> Set<URL> {
        guard depth <= maxDepth else { return [] }
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            if matchCandidate(item, identity: identity, mode: .balanced) {
                found.insert(item)
            }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let sub = await deepScan(item, identity: identity, depth: depth + 1, maxDepth: maxDepth)
                found.formUnion(sub)
            }
        }
        return found
    }

    private func matchCandidate(_ url: URL, identity: AppIdentity, mode: ScanMode = .balanced) -> Bool {
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

        // Balanced: vendor, contains, executable matching
        if identity.vendorNames.contains(name) {
            return true
        }
        if identity.vendorNames.contains(where: { lowerName.contains($0.lowercased()) }) {
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
        let bases = ["\(home)/Library/Application Support", "\(home)/Library/Caches", "\(home)/Library/Logs"]
        for (vendor, product) in vendorRoots {
            for base in bases {
                let vendorURL = URL(fileURLWithPath: base).appendingPathComponent(vendor)
                guard fileManager.fileExists(atPath: vendorURL.path) else { continue }
                if let product {
                    let productURL = vendorURL.appendingPathComponent(product)
                    if fileManager.fileExists(atPath: productURL.path) {
                        found.insert(productURL)
                        found.formUnion(await deepScan(productURL, identity: identity, depth: 0, maxDepth: maxDepth))
                    }
                } else {
                    found.insert(vendorURL)
                    found.formUnion(await deepScan(vendorURL, identity: identity, depth: 0, maxDepth: maxDepth))
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
            tokens.formUnion(["parallels", ".pvm"])
        }
        if bid.contains("vmware") || name.contains("vmware") {
            tokens.formUnion(["vmware", "virtual machines", ".vmx"])
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

    private func scanVMUserData(identity: AppIdentity, home: String) async -> Set<URL> {
        let tokens = vmDataTokens(for: identity)
        guard !tokens.isEmpty else { return [] }
        var found = Set<URL>()
        let roots = ["\(home)/Documents", "\(home)/Desktop", "/Users/Shared"]
        for root in roots {
            let url = URL(fileURLWithPath: root)
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
            if tokens.contains(where: { lower.contains($0) }) || item.pathExtension.lowercased() == "pvm" || item.pathExtension.lowercased() == "vmx" {
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
        let home = NSHomeDirectory()
        let names = Set([identity.appName, identity.executableName].filter { !$0.isEmpty })
        for name in names {
            queries.append(("kMDItemFSName == '\(mdfindEscape(name))*'cd", "\(home)/Library"))
        }

        var urls = Set<URL>()
        for (query, onlyIn) in queries {
            var arguments: [String] = []
            if let onlyIn { arguments += ["-onlyin", onlyIn] }
            arguments.append(query)
            if let result = try? await commandRunner.run(command: "/usr/bin/mdfind", arguments: arguments) {
                for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
                    urls.insert(URL(fileURLWithPath: line))
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
