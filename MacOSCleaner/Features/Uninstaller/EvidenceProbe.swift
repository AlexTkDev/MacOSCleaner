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

        // Identity checks
        if lowerFileName == lowerBundleID {
            evidence.insert(.bundleIDExact)
        } else if lowerFileName.hasPrefix(lowerBundleID + ".") {
            evidence.insert(.bundleIDPrefix)
        }
        if url.pathExtension.lowercased() == "app",
           Bundle(url: url)?.bundleIdentifier?.lowercased() == lowerBundleID {
            evidence.insert(.bundleIDExact)
        }

        if lowerFileName == lowerAppName {
            evidence.insert(.appNameExact)
        } else if lowerFileName.hasPrefix(lowerAppName + " ")
                    || lowerFileName.hasPrefix(lowerAppName + "-")
                    || lowerFileName.hasPrefix(lowerAppName + ".") {
            evidence.insert(.appNamePrefix)
        }

        // CFBundleName is the app's own declared product name (iTerm2 for iTerm.app,
        // Chrome for Google Chrome.app). Trusted only directly inside Library base
        // dirs or a vendor dir — deep matches on short product names are too risky.
        if let lowerBundleName = identity.bundleName?.lowercased(), !lowerBundleName.isEmpty,
           Self.libraryBaseDirNames.contains(parentFolder) || lowerVendorNames.contains(parentFolder.lowercased()) {
            if lowerFileName == lowerBundleName {
                evidence.insert(.appNameExact)
            } else if lowerFileName.hasPrefix(lowerBundleName + " ")
                        || lowerFileName.hasPrefix(lowerBundleName + "-")
                        || lowerFileName.hasPrefix(lowerBundleName + ".") {
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
            } else if lowerFileName == "group.\(lowerBundleID)" || lowerFileName.hasPrefix("group.\(lowerBundleID).") {
                evidence.insert(.appGroup)
            } else if let teamID = identity.teamID, !teamID.isEmpty, fileName.hasPrefix(teamID + ".") {
                let suffix = String(fileName.dropFirst(teamID.count + 1)).lowercased()
                // HUAQ24HBR6.dev.orbstack / TC3Q7MAJXF.com.adguard.mac — app-owned container
                if suffix == lowerBundleID || suffix.hasPrefix(lowerBundleID + ".") {
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
            if lowerFileName == lowerAppName
                || lowerFileName.hasPrefix(lowerAppName + " ")
                || lowerFileName.hasPrefix(lowerAppName + "-")
                || lowerFileName.hasPrefix(lowerAppName + ".") {
                evidence.insert(.appNameExact)
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

    /// TeamID container suffix matches bundle ID tail (dev.orbstack ↔ com.docker.orbstack).
    static func bundleIDSuffixMatch(_ containerSuffix: String, bundleID: String) -> Bool {
        let suffixParts = containerSuffix.split(separator: ".")
        let bundleParts = bundleID.split(separator: ".")
        guard let tail = suffixParts.last, tail.count >= 3 else { return false }
        return bundleParts.suffix(2).map(String.init).joined(separator: ".") == suffixParts.suffix(2).map(String.init).joined(separator: ".")
            || bundleParts.last.map(String.init) == String(tail)
    }
}
