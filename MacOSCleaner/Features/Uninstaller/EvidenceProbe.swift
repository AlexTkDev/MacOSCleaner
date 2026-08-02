import AppKit
import Foundation

public actor EvidenceProbe {
    private let commandRunner: any CommandRunning
    private let codesignCache: CodesignCache
    private let plistCache: PlistContentCache

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        codesignCache: CodesignCache = CodesignCache(),
        plistCache: PlistContentCache = PlistContentCache()
    ) {
        self.commandRunner = commandRunner
        self.codesignCache = codesignCache
        self.plistCache = plistCache
    }

    public func probe(url: URL, identity: AppIdentity) async -> Set<Evidence> {
        var evidence = Set<Evidence>()

        let fileName = url.lastPathComponent
        let parentFolder = url.deletingLastPathComponent().lastPathComponent
        let path = url.path.lowercased()

        // Case-insensitive identity checks: Electron apps often use lowercase
        // data dirs (~/Library/Application Support/discord for "Discord").
        let lowerFileName = fileName.lowercased()
        let lowerBundleID = identity.bundleID.lowercased()
        let lowerAppName = identity.appName.lowercased()
        let lowerVendorNames = Set(identity.vendorNames.map { $0.lowercased() })

        // Identity checks & TeamID/Group stripped filename
        var strippedFileName = lowerFileName
        if let teamID = identity.teamID, !teamID.isEmpty, strippedFileName.hasPrefix(teamID.lowercased() + ".") {
            strippedFileName = String(strippedFileName.dropFirst(teamID.count + 1))
        }
        if strippedFileName.hasPrefix("group.") {
            strippedFileName = String(strippedFileName.dropFirst(6))
        }

        if lowerFileName == lowerBundleID || strippedFileName == lowerBundleID {
            evidence.insert(.bundleIDExact)
        } else if lowerFileName.hasPrefix(lowerBundleID + ".") || strippedFileName.hasPrefix(lowerBundleID + ".") || (strippedFileName.contains(".") && lowerBundleID.hasPrefix(strippedFileName)) {
            evidence.insert(.bundleIDPrefix)
        }
        if url.pathExtension.lowercased() == "app",
           Bundle(url: url)?.bundleIdentifier?.lowercased() == lowerBundleID {
            evidence.insert(.bundleIDExact)
        }
        
        if url.pathExtension.lowercased() == "app" {
            if let lsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identity.bundleID),
               lsURL.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() {
                evidence.insert(.launchServicesRegistered)
            }
        }

        let appNameHit = Self.appNameMatchesFileName(fileName, appName: identity.appName)
        if appNameHit.exact {
            evidence.insert(.appNameExact)
        } else if appNameHit.prefix, !Self.looksLikeSourceFileName(lowerFileName) {
            evidence.insert(.appNamePrefix)
        }

        // CFBundleName is the app's own declared product name (iTerm2 for iTerm.app,
        // Chrome for Google Chrome.app). Trusted only directly inside Library base
        // dirs or a vendor dir — deep matches on short product names are too risky.
        if let bundleName = identity.bundleName, !bundleName.isEmpty,
           Self.libraryBaseDirNames.contains(parentFolder) || lowerVendorNames.contains(parentFolder.lowercased()) {
            let bundleHit = Self.appNameMatchesFileName(fileName, appName: bundleName)
            if bundleHit.exact {
                evidence.insert(.appNameExact)
            } else if bundleHit.prefix, !Self.looksLikeSourceFileName(lowerFileName) {
                evidence.insert(.appNamePrefix)
            }
        }

        if lowerVendorNames.contains(lowerFileName) || lowerVendorNames.contains(parentFolder.lowercased()) {
            evidence.insert(.vendorName)
        }

        if identity.frameworkNames.contains(fileName) || identity.frameworkNames.contains(fileName.replacingOccurrences(of: ".framework", with: "")) {
            evidence.insert(.frameworkName)
        }

        if identity.xpcServiceNames.contains(fileName) || identity.xpcServiceNames.contains(fileName.replacingOccurrences(of: ".xpc", with: "")) {
            evidence.insert(.xpcServiceName)
        }

        if identity.plugInNames.contains(fileName) || identity.plugInNames.contains(fileName.replacingOccurrences(of: ".bundle", with: "")) {
            evidence.insert(.plugInName)
        }

        if lowerFileName == identity.executableName.lowercased() {
            evidence.insert(.executableName)
        }

        // Container checks
        if parentFolder == "Containers" && lowerFileName == lowerBundleID {
            evidence.insert(.container)
        }
        if parentFolder == "Group Containers" {
            // Entitlements are ground truth: TC3Q7MAJXF.com.adguard.mac belongs to
            // AdGuard VPN (com.adguard.mac.vpn) because its signature declares it.
            if identity.appGroups.contains(fileName) {
                evidence.insert(.appGroup)
            } else if lowerFileName == "group.\(lowerBundleID)" || lowerFileName.hasPrefix("group.\(lowerBundleID).") || strippedFileName.hasPrefix(lowerBundleID) {
                evidence.insert(.appGroup)
            } else if let teamID = identity.teamID, !teamID.isEmpty, fileName.hasPrefix(teamID + ".") {
                let suffix = String(fileName.dropFirst(teamID.count + 1)).lowercased()
                // HUAQ24HBR6.dev.orbstack / TC3Q7MAJXF.com.adguard.mac — app-owned container
                if suffix == lowerBundleID || suffix.hasPrefix(lowerBundleID + ".") || (suffix.contains(".") && lowerBundleID.hasPrefix(suffix)) {
                    evidence.insert(.appGroup)
                } else if Self.bundleIDSuffixMatch(suffix, bundleID: lowerBundleID) {
                    evidence.insert(.appGroup)
                } else {
                    // UBF8T346G9.Office — shared vendor container, weak evidence
                    evidence.insert(.vendorName)
                }
            }
        }

        // Library cache/support folders named after the bundle ID (com.microsoft.autoupdate2, …)
        if path.contains("/library/caches/") || path.contains("/library/logs/") {
            if lowerFileName == lowerBundleID || lowerFileName.hasPrefix(lowerBundleID + ".") {
                evidence.insert(.bundleIDExact)
            }
        }
        if path.contains("/library/application support/") {
            let hit = Self.appNameMatchesFileName(fileName, appName: identity.appName)
            let parentIsBase = parentFolder == "Application Support"
            let parentIsVendor = lowerVendorNames.contains(parentFolder.lowercased())
            // Direct AS child, or product under vendor hub (Google/AndroidStudio*).
            // Deeper foreign trees (OtherApp/Data/…) stay on the generic name checks only.
            if hit.exact || hit.prefix, parentIsBase || parentIsVendor {
                evidence.insert(.appNameExact)
            }
        }

        // Dotdirs (~/.anydesk, ~/.orbstack): leading-dot name matching app token.
        if lowerFileName.hasPrefix(".") {
            let hit = Self.appNameMatchesFileName(fileName, appName: identity.appName)
            if hit.exact {
                evidence.insert(.appNameExact)
            } else if hit.prefix {
                evidence.insert(.appNamePrefix)
            }
        }

        // System integration. App name must start a token ("ArcUpdater.plist" yes,
        // "com.searchmarquis.plist" no) so short names don't match foreign agents.
        let nameMatchesIdentifier = path.contains(lowerBundleID) || Self.tokenPrefixMatch(lowerFileName, lowerAppName)
        if path.contains("/launchagents/") && nameMatchesIdentifier {
            evidence.insert(.launchAgent)
        }
        if path.contains("/launchdaemons/") && nameMatchesIdentifier {
            evidence.insert(.launchDaemon)
        }

        // Application Scripts
        if path.contains("/application scripts/\(identity.bundleID.lowercased())") {
            evidence.insert(.extension)
        }

        // Electron / VS Code–style cache detection
        if identity.isElectron {
            let electronDirs = [
                "Cache", "Code Cache", "GPUCache", "CachedData", "Backups",
                "Local Storage", "Session Storage", "IndexedDB", "Network",
            ]
            let supportNames = [lowerAppName, identity.bundleName?.lowercased()].compactMap { $0 }.filter { !$0.isEmpty }
            if electronDirs.contains(fileName),
               supportNames.contains(where: { path.contains("/application support/\($0)") }) {
                evidence.insert(.electronCache)
            }
        }

        // JetBrains config
        if identity.isJetBrains && path.contains("/application support/jetbrains") {
            evidence.insert(.jetBrainsConfig)
        }

        // Flutter build
        if identity.isFlutter && (path.contains(".dart_tool") || path.contains("/build/flutter")) {
            evidence.insert(.flutterBuild)
        }

        // Code signature probe
        let binaryExts: Set<String> = ["", "app", "bundle", "kext", "framework", "dylib", "xpc"]
        let fileExt = url.pathExtension
        if binaryExts.contains(fileExt) || fileExt.isEmpty {
            if let candidateTeamID = await codesignCache.getTeamID(url: url, commandRunner: commandRunner) {
                if candidateTeamID == identity.teamID && identity.teamID != nil {
                    evidence.insert(.teamID)
                }
            }
            if let auth = identity.signingAuthority {
                let result = try? await commandRunner.run(command: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", url.path])
                if let output = result?.stderr, output.contains(auth) {
                    evidence.insert(.developerSignature)
                }
            }
        }

        // Plist content probe. Bundle ID is unique enough for substring match; the app
        // name must be a whole word ("/Applications/Arc.app" yes, "architecture" no).
        if url.pathExtension == "plist" || fileName.hasSuffix(".plist") {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size > 0 && size < 512 * 1024 {
                if let content = await plistCache.getContent(url: url) {
                    let lower = content.lowercased()
                    if lower.contains(lowerBundleID) || Self.wordBoundaryMatch(lower, lowerAppName) {
                        evidence.insert(.plistContent)
                    }
                }
            }
        }

        // JSON/XML/YAML config content probe
        let configExts: Set<String> = ["json", "yaml", "yml", "xml", "conf"]
        if configExts.contains(url.pathExtension.lowercased()) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size > 0 && size < 256 * 1024,
               let data = try? Data(contentsOf: url),
               let content = String(data: data, encoding: .utf8)?.lowercased() {
                if content.contains(lowerBundleID) || Self.wordBoundaryMatch(content, lowerAppName) {
                    evidence.insert(.fileContent)
                }
            }
        }

        return evidence
    }

    /// Standard Library residual roots where a name match is meaningful context.
    static let libraryBaseDirNames: Set<String> = [
        "Application Support", "Caches", "Preferences", "ByHost", "Logs",
        "Containers", "Group Containers", "WebKit", "HTTPStorages",
        "Saved Application State", "Application Scripts",
        "LaunchAgents", "LaunchDaemons",
    ]

    // MARK: - Name matching helpers

    /// Needle starts a token in haystack: "arc" matches "arc helper"/"arcupdater", not "searchmarquis".
    static func tokenPrefixMatch(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: needle)
        return haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Needle is a whole word in haystack: "arc" matches "arc.app", not "architecture".
    static func wordBoundaryMatch(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: needle) + "(?![\\p{L}\\p{N}])"
        return haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Android Studio" ↔ "AndroidStudio2026.1.2"; ".anydesk" ↔ "AnyDesk".
    static func compactIdentityToken(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Mega-vendor head tokens must not alone equal the app display name
    /// ("Google" ↛ "Google Chrome") — those roots are shared suite folders.
    private static let megaVendorNameTokens: Set<String> = [
        "google", "microsoft", "adobe", "oracle", "apple",
    ]

    /// App display name vs on-disk folder/file (dotdirs, spaced vs compact JetBrains/Google IDE dirs).
    static func appNameMatchesFileName(_ fileName: String, appName: String) -> (exact: Bool, prefix: Bool) {
        let lower = fileName.lowercased()
        let bare = lower.hasPrefix(".") ? String(lower.dropFirst()) : lower
        let app = appName.lowercased()
        guard !app.isEmpty, bare.count >= 2 else { return (false, false) }

        if bare == app { return (true, false) }
        if bare.hasPrefix(app + " ") || bare.hasPrefix(app + "-") || bare.hasPrefix(app + "_") {
            return (false, true)
        }
        // Residual suffixes: AnyDesk.plist — callers must reject source files (Cursor.java).
        if bare.hasPrefix(app + ".") { return (false, true) }

        let cFile = compactIdentityToken(bare)
        let cApp = compactIdentityToken(app)
        guard cApp.count >= 4 else { return (false, false) }
        if cFile == cApp { return (true, false) }
        // Compact prefix needs length ≥5 to avoid short-token collisions (code→codecache).
        if cApp.count >= 5, cFile.hasPrefix(cApp), cFile.count > cApp.count {
            return (false, true)
        }

        // Multi-word products: ".antigravity" ↔ "Antigravity IDE", ".android" ↔ "Android Studio".
        // Skip mega-vendor heads so bare "Google" never equals "Google Chrome".
        let rawWords = app.split { $0 == " " || $0 == "-" || $0 == "_" }
            .map(String.init)
            .filter { !$0.isEmpty }
        if rawWords.count >= 2 {
            let head = rawWords[0]
            if head.count >= 4, !megaVendorNameTokens.contains(head) {
                let cHead = compactIdentityToken(head)
                if bare == head || cFile == cHead { return (true, false) }
                if cHead.count >= 5, cFile.hasPrefix(cHead), cFile.count > cHead.count {
                    return (false, true)
                }
            }
        }
        return (false, false)
    }

    static func looksLikeSourceFileName(_ lowerName: String) -> Bool {
        guard lowerName.contains("."), !lowerName.hasPrefix(".") else { return false }
        let sourceExts: Set<String> = [
            "java", "swift", "m", "mm", "h", "hpp", "c", "cpp", "cc",
            "js", "jsx", "ts", "tsx", "py", "rb", "go", "kt", "kts",
            "rs", "cs", "scala", "groovy", "dart",
        ]
        return sourceExts.contains((lowerName as NSString).pathExtension)
    }

    /// TeamID container suffix matches bundle ID tail (dev.orbstack ↔ com.docker.orbstack).
    static func bundleIDSuffixMatch(_ containerSuffix: String, bundleID: String) -> Bool {
        let suffixParts = containerSuffix.split(separator: ".")
        let bundleParts = bundleID.split(separator: ".")
        guard let tail = suffixParts.last, tail.count >= 3 else { return false }
        return bundleParts.suffix(2).map(String.init).joined(separator: ".") == suffixParts.suffix(2).map(String.init).joined(separator: ".")
            || bundleParts.last.map(String.init) == String(tail)
    }
}
