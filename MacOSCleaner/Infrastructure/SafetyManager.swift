import Foundation

public enum SafetyError: Error, Equatable, LocalizedError {
    case pathNormalizationFailed
    case symlinkEscapeAttempted
    case protectedPath(String)

    public var errorDescription: String? {
        switch self {
        case .pathNormalizationFailed:
            return "Path normalization failed"
        case .symlinkEscapeAttempted:
            return "Symlink escape attempted"
        case .protectedPath(let path):
            return "Protected path: \(path)"
        }
    }
}

/// Context of a deletion request. Regular cleanup must never touch login/session
/// data; a full app uninstall is allowed to remove the app's user data only when
/// the target belongs to the app being uninstalled.
public enum DeletionPolicy: Sendable, Equatable {
    case cleanup
    case uninstall
    case uninstallApp(bundleID: String?)
    case userSelected

    public var isUninstall: Bool {
        switch self {
        case .uninstall, .uninstallApp:
            return true
        case .cleanup, .userSelected:
            return false
        }
    }
}

public struct SafetyManager: Sendable {
    private enum BrowserCacheLayout: Sendable {
        case chromium(channelSubdirs: Set<String> = [])
        case firefox
        case safariLibrary
        case browserContainer
        case opaqueUserData
    }

    private struct BrowserRootSpec: Sendable {
        let canonicalRoot: String
        let lowerRoot: String
        let ownerBundleIDs: Set<String>
        let layout: BrowserCacheLayout
        let isSystemProtected: Bool

        init(
            root: String,
            ownerBundleIDs: Set<String>,
            layout: BrowserCacheLayout,
            isSystemProtected: Bool = false
        ) {
            let normalized = NormalizedPath.string(URL(fileURLWithPath: root).standardizedFileURL.path)
            self.canonicalRoot = normalized
            self.lowerRoot = normalized.lowercased()
            self.ownerBundleIDs = Set(ownerBundleIDs.map { $0.lowercased() })
            self.layout = layout
            self.isSystemProtected = isSystemProtected
        }
    }

    private let home: String
    private let homeVariants: [String]
    private let refuseList: [String]
    private let allowedExceptions: [String]
    private let customAllowedExceptions: [String]

    // OS-owned dirs living inside allowed exception roots (e.g. /Library/Application Support).
    // Checked before exceptions, so they can never be deleted.
    private let hardRefuseList: [String]

    // Roots that custom exceptions must never override.
    private let immutableRefuseRoots: [String]

    // Directories that must never be deleted wholesale, though their children may be
    // (e.g. ~/Library/Preferences itself vs. an app's plist inside it). Exact match only.
    private let exactRefuseLowerMap: [String: String]

    // Browser user-data roots holding logins, cookies, extensions, and site sessions.
    private let browserSpecs: [BrowserRootSpec]

    // Lowercased basenames of credential/session files (Chromium family) protected
    // anywhere under Application Support during cleanup.
    private let credentialFileNames: Set<String>

    private static let chromiumRootCacheDirs: Set<String> = [
        "grshadercache", "shadercache", "graphite_dawn_cache", "crashpad",
    ]
    private static let chromiumProfileCacheDirs: Set<String> = [
        "cache", "code cache", "gpucache",
    ]
    private static let firefoxProfileCacheDirs: Set<String> = [
        "cache2", "startupcache", "thumbnails",
    ]
    private static let safariLibraryCacheDirs: Set<String> = [
        "favicon cache", "touch icons cache", "template icons",
    ]
    private static let browserProtectedSegments: Set<String> = [
        "extensions",
        "extension state",
        "extension rules",
        "extension scripts",
        "local extension settings",
        "sync extension settings",
        "managed extension settings",
        "local extension storage",
        "local storage",
        "session storage",
        "indexeddb",
        "sync data",
        "sessions",
        "nativemessaginghosts",
        "external extensions",
        "databases",
        "file system",
        "blob_storage",
        "shared_proto_db",
        "autofillstrikedatabase",
        "network",
        "cookies",
        "login data",
        "web data",
    ]

    private let fileSystemContext: FileSystemContext?

    public init(allowedExceptions: [String] = [], homeDirectory: String? = nil, fileSystemContext: FileSystemContext? = nil) {
        let rawHome = homeDirectory
            ?? fileSystemContext?.homePath
            ?? NSHomeDirectory()
        let stdHome = NormalizedPath.string(URL(fileURLWithPath: rawHome).standardizedFileURL.path)
        let resolvedHome = NormalizedPath.resolvedString(stdHome)
        let homeVariants = resolvedHome == stdHome ? [stdHome] : [stdHome, resolvedHome]

        self.home = stdHome
        self.homeVariants = homeVariants
        self.fileSystemContext = fileSystemContext

        self.immutableRefuseRoots = [
            "/System",
            "/Applications",
            "/Users/Shared",
            "/opt",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/private",
            "/etc",
            // Note: /var is a Darwin alias of /private/var — allow narrow /var/folders via exceptions.
            "/nix",
        ]

        var refuse: [String] = [
            "/System",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/private",
            "/etc",
            "/var/root",
            "/tmp",
            "/opt",
            "/nix",
            "/Applications",
            "/Users/Shared",
        ]
        for h in homeVariants {
            refuse.append(contentsOf: [
                "\(h)/.ssh",
                "\(h)/.gnupg",
                "\(h)/Documents",
                "\(h)/Desktop",
                "\(h)/Downloads",
                "\(h)/Movies",
                "\(h)/Music",
                "\(h)/Pictures",
                "\(h)/Backups",
            ])
        }
        refuse.append("/")
        self.refuseList = Self.dedupePreservingOrder(refuse)

        var defaultExceptions: [String] = [
            "/Library/Application Support",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Receipts",
            "/Library/Internet Plug-Ins",
            // /private/var/folders and /var/folders hold Darwin caches — allow only the
            // per-user cache roots (…/C, …/T), not arbitrary temp homes under /var/folders.
            "/private/var/folders",
            "/var/folders",
            "/private/var/db/receipts",
            "/private/tmp",
            "/tmp",
            "/usr/local",
            "/Library/Caches",
            "/Library/Logs",
            "/Library/PrivilegedHelperTools",
            "/Library/PreferencePanes",
            "/Library/Spotlight",
            "/Library/QuickLook",
            "/Library/Input Methods",
            "/Library/Audio",
            "/Library/SystemExtensions",
            "/Library/StagedExtensions",
            "/Library/Preferences",
            "/opt/homebrew/Cellar",
            "/opt/homebrew/Caskroom",
            "/usr/local/Cellar",
            "/usr/local/Caskroom",
            URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path,
            URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL.path,
        ]
        for h in homeVariants {
            defaultExceptions.append(contentsOf: [
                "\(h)/Library",
                "\(h)/Library/Application Support/MacOSCleaner",
                "\(h)/Library/Application Scripts/input.MacOSCleaner",
                "\(h)/Library/Caches",
                "\(h)/Library/Developer",
                "\(h)/Library/Logs",
                "\(h)/Library/Application Support",
                "\(h)/Library/Containers",
                "\(h)/Library/Android",
                "\(h)/Library/Safari",
                "\(h)/Library/WebKit",
            ])
        }

        self.customAllowedExceptions = allowedExceptions
        self.allowedExceptions = Self.dedupePreservingOrder(defaultExceptions + allowedExceptions)

        var hardRefuse: [String] = [
            "/Library/Application Support/Apple",
            "/Library/Application Support/Script Editor",
            "/Library/Application Support/com.apple.TCC",
            "/var/db/dslocal",
            "/private/var/db/dslocal",
        ]
        for h in homeVariants {
            hardRefuse.append(contentsOf: [
                "\(h)/Library/Application Support/Apple",
                "\(h)/Library/Keychains",
                "\(h)/Library/Calendars",
                "\(h)/Library/Reminders",
                "\(h)/Library/Contacts",
                "\(h)/Library/Application Support/AddressBook",
                "\(h)/Library/Messages",
                "\(h)/Library/Mobile Documents",
                "\(h)/Library/Preferences/com.google.Keystone.Agent.plist",
                "\(h)/Library/Google/GoogleSoftwareUpdate",
                "\(h)/Library/Application Support/Google/GoogleUpdater",
                "\(h)/Library/Caches/com.google.SoftwareUpdate",
                "\(h)/Library/Caches/com.google.GoogleUpdater",
                "\(h)/Library/HTTPStorages/com.google.GoogleUpdater",
                "\(h)/Library/LaunchAgents/com.google.keystone.agent.plist",
                "\(h)/Library/LaunchAgents/com.google.keystone.xpcservice.plist",
                "\(h)/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist",
                "\(h)/Library/Application Support/Chrome/Default/Login Data",
                "\(h)/Library/Application Support/Chrome/Default/Cookies",
                "\(h)/Library/Application Support/Google/Chrome/Default/Login Data",
                "\(h)/Library/Application Support/Google/Chrome/Default/Cookies",
                "\(h)/Library/Application Support/com.apple.TCC",
                "\(h)/.ssh",
                "\(h)/.gnupg",
            ])
        }
        self.hardRefuseList = Self.dedupePreservingOrder(hardRefuse)

        var specs: [BrowserRootSpec] = [
            BrowserRootSpec(
                root: "/Library/Application Support/Google/Chrome",
                ownerBundleIDs: [],
                layout: .opaqueUserData,
                isSystemProtected: true
            ),
            BrowserRootSpec(
                root: "/Library/Google/Chrome",
                ownerBundleIDs: [],
                layout: .opaqueUserData,
                isSystemProtected: true
            ),
        ]
        for h in homeVariants {
            let appSupport = "\(h)/Library/Application Support"
            specs.append(contentsOf: [
                BrowserRootSpec(root: "\(appSupport)/Google/Chrome", ownerBundleIDs: ["com.google.chrome"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Google/Chrome Beta", ownerBundleIDs: ["com.google.chrome.beta"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Google/Chrome Canary", ownerBundleIDs: ["com.google.chrome.canary"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Google/Chrome Dev", ownerBundleIDs: ["com.google.chrome.dev"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Chrome", ownerBundleIDs: ["com.google.chrome"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Chromium", ownerBundleIDs: ["org.chromium.chromium"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/BraveSoftware/Brave-Browser", ownerBundleIDs: ["com.brave.browser"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/BraveSoftware/Brave-Browser-Beta", ownerBundleIDs: ["com.brave.browser.beta"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/BraveSoftware/Brave-Browser-Nightly", ownerBundleIDs: ["com.brave.browser.nightly"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Microsoft Edge", ownerBundleIDs: ["com.microsoft.edgemac"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Microsoft Edge Beta", ownerBundleIDs: ["com.microsoft.edgemac.beta"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Microsoft Edge Canary", ownerBundleIDs: ["com.microsoft.edgemac.canary"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Microsoft Edge Dev", ownerBundleIDs: ["com.microsoft.edgemac.dev"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Arc", ownerBundleIDs: ["company.thebrowser.browser"], layout: .chromium(channelSubdirs: ["user data"])),
                BrowserRootSpec(root: "\(appSupport)/Firefox", ownerBundleIDs: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"], layout: .firefox),
                BrowserRootSpec(root: "\(appSupport)/Mozilla", ownerBundleIDs: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"], layout: .firefox),
                BrowserRootSpec(root: "\(appSupport)/Vivaldi", ownerBundleIDs: ["com.vivaldi.vivaldi"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Yandex", ownerBundleIDs: ["ru.yandex.desktop.yandex-browser"], layout: .chromium(channelSubdirs: ["yandexbrowser"])),
                BrowserRootSpec(root: "\(appSupport)/com.operasoftware.Opera", ownerBundleIDs: ["com.operasoftware.opera"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/com.operasoftware.OperaGX", ownerBundleIDs: ["com.operasoftware.operagx"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/com.operasoftware.OperaDeveloperEdition", ownerBundleIDs: ["com.operasoftware.operadeveloperedition"], layout: .chromium()),
                BrowserRootSpec(root: "\(appSupport)/Opera Software", ownerBundleIDs: ["com.operasoftware.opera", "com.operasoftware.operagx", "com.operasoftware.operadeveloperedition"], layout: .chromium(channelSubdirs: ["opera stable", "opera gx stable", "opera developer"])),
                BrowserRootSpec(root: "\(appSupport)/Orion", ownerBundleIDs: ["com.kagi.kagimacos"], layout: .opaqueUserData),
                BrowserRootSpec(root: "\(appSupport)/DuckDuckGo", ownerBundleIDs: ["com.duckduckgo.macos.browser"], layout: .opaqueUserData),
                BrowserRootSpec(root: "\(appSupport)/TorBrowser-Data", ownerBundleIDs: ["org.torproject.torbrowser"], layout: .opaqueUserData),
                BrowserRootSpec(root: "\(appSupport)/Waterfox", ownerBundleIDs: ["net.waterfox.waterfox"], layout: .firefox),
                BrowserRootSpec(root: "\(appSupport)/LibreWolf", ownerBundleIDs: ["io.gitlab.librewolf-community"], layout: .firefox),
                BrowserRootSpec(root: "\(appSupport)/MullvadBrowser", ownerBundleIDs: ["net.mullvad.mullvadbrowser"], layout: .firefox),
                BrowserRootSpec(root: "\(h)/Library/Safari", ownerBundleIDs: [], layout: .safariLibrary, isSystemProtected: true),
                BrowserRootSpec(root: "\(h)/Library/Containers/com.apple.Safari", ownerBundleIDs: [], layout: .browserContainer, isSystemProtected: true),
                BrowserRootSpec(root: "\(h)/Library/WebKit/com.apple.Safari", ownerBundleIDs: [], layout: .opaqueUserData, isSystemProtected: true),
                BrowserRootSpec(root: "\(h)/Library/Containers/com.duckduckgo.macos.browser", ownerBundleIDs: ["com.duckduckgo.macos.browser"], layout: .browserContainer),
                BrowserRootSpec(root: "\(h)/Library/Containers/com.kagi.kagimacOS", ownerBundleIDs: ["com.kagi.kagimacos"], layout: .browserContainer),
            ])
        }
        self.browserSpecs = specs

        self.credentialFileNames = [
            "login data", "login data for account", "cookies",
            "web data", "account web data", "local state", "secure preferences",
            "cookies.sqlite", "cookies.binarycookies",
            "logins.json", "key4.db", "cert9.db",
            "places.sqlite", "favicons.sqlite", "formhistory.sqlite",
            "sessionstore.jsonlz4", "logins-backup.json",
        ]

        var exactRefuse: [String] = [
            "/Users",
            "/Library/Application Support",
            "/Library/Preferences",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/PrivilegedHelperTools",
            "/tmp",
            "/private/tmp",
            URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path,
            URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL.path,
        ]
        for h in homeVariants {
            exactRefuse.append(contentsOf: [
                h,
                "\(h)/Library",
                "\(h)/Library/Preferences",
                "\(h)/Library/Preferences/ByHost",
                "\(h)/Library/Application Support",
                "\(h)/Library/Caches",
                "\(h)/Library/Containers",
                "\(h)/Library/Group Containers",
                "\(h)/Library/Logs",
                "\(h)/Library/WebKit",
                "\(h)/Library/HTTPStorages",
                "\(h)/Library/Application Scripts",
                "\(h)/Library/Developer",
                "\(h)/Library/Messages",
                "\(h)/Library/Mobile Documents",
                "\(h)/Library/Cookies",
                "\(h)/Backups",
                "\(h)/Library/LaunchAgents",
            ])
        }
        var exactMap: [String: String] = [:]
        for item in exactRefuse {
            let normalized = NormalizedPath.string(item)
            let key = normalized.lowercased()
            if exactMap[key] == nil {
                exactMap[key] = normalized
            }
        }
        self.exactRefuseLowerMap = exactMap
    }

    public func validate(url: URL, policy: DeletionPolicy = .cleanup) throws {
        guard url.isFileURL else {
            throw SafetyError.pathNormalizationFailed
        }

        let standardized = url.standardizedFileURL
        let path = NormalizedPath.string(standardized.path)

        guard !path.isEmpty else {
            throw SafetyError.pathNormalizationFailed
        }

        if let ctx = fileSystemContext {
            try ctx.assertAllowedForMutation(standardized)
        }

        try validateSymlinkComponents(of: standardized)

        let resolvedPath = NormalizedPath.string(standardized.resolvingSymlinksInPath().standardizedFileURL.path)
        let pathsToCheck = resolvedPath == path ? [path] : [path, resolvedPath]

        for p in pathsToCheck {
            let lowerP = p.lowercased()

            for refused in hardRefuseList {
                if NormalizedPath.isEqualOrDescendant(lowerP, of: refused.lowercased()) {
                    throw SafetyError.protectedPath(refused)
                }
            }

            // Apple system group containers must never be removed
            for h in homeVariants {
                let lowerGC = "\(h.lowercased())/library/group containers"
                if lowerP == lowerGC {
                    throw SafetyError.protectedPath("\(h)/Library/Group Containers")
                }
                if lowerP.hasPrefix("\(lowerGC)/group.com.apple")
                    || lowerP.hasPrefix("\(lowerGC)/com.apple") {
                    throw SafetyError.protectedPath("\(h)/Library/Group Containers")
                }
            }

            if let exactRefused = exactRefuseLowerMap[lowerP] {
                throw SafetyError.protectedPath(exactRefused)
            }

            // Protect ~/Library/Mail under uninstall unless inside ~/Library/Mail/Bundles
            if policy.isUninstall {
                for h in homeVariants {
                    let lowerMail = "\(h.lowercased())/library/mail"
                    let lowerBundles = "\(h.lowercased())/library/mail/bundles"
                    if NormalizedPath.isEqualOrDescendant(lowerP, of: lowerMail)
                        && !NormalizedPath.isEqualOrDescendant(lowerP, of: lowerBundles) {
                        throw SafetyError.protectedPath("\(h)/Library/Mail")
                    }
                }
            }

            if let refused = browserProtectedPath(p, lowerP: lowerP, policy: policy) {
                throw SafetyError.protectedPath(refused)
            }

            if policy == .cleanup, let refused = cleanupProtectedPath(p, lowerPath: lowerP) {
                throw SafetyError.protectedPath(refused)
            }

            // Under cleanup, home dot-directories are blocked unless they match an explicit
            // regenerable cache in EmbeddedCleanupPaths, an opt-in AI model root, or custom exception.
            if policy == .cleanup {
                for h in homeVariants {
                    let trimmedHome = h.hasSuffix("/") ? String(h.dropLast()) : h
                    let lowerHome = trimmedHome.lowercased()
                    if lowerP == "\(lowerHome)/go/pkg/mod" {
                        throw SafetyError.protectedPath("\(trimmedHome)/go/pkg/mod")
                    }
                    if lowerP.hasPrefix("\(lowerHome)/.") && lowerP != "\(lowerHome)/.ds_store" {
                        let hasCustomException = customAllowedExceptions.contains { exception in
                            NormalizedPath.isEqualOrDescendant(lowerP, of: exception.lowercased())
                        }
                        if !hasCustomException
                            && !Self.isRegenerableCachePath(p, homeVariants: homeVariants)
                            && !Self.isReviewableAIModelPath(p, homeVariants: homeVariants) {
                            throw SafetyError.protectedPath(p)
                        }
                    }
                }
            }

            // Custom exceptions never override immutable system / shared roots themselves.
            // Only pre-declared narrow subpaths (Homebrew Cellar, /Library/LaunchAgents, …) may pass.
            if isUnderImmutableRefuseRoot(lowerP) {
                if lowerP == "/applications" || lowerP.hasPrefix("/applications/") {
                    if policy.isUninstall, lowerP != "/applications" {
                        continue
                    }
                    throw SafetyError.protectedPath("/Applications")
                }

                let hasNarrowException = allowedExceptions.contains { exception in
                    let lowerException = exception.lowercased()
                    guard NormalizedPath.isEqualOrDescendant(lowerP, of: lowerException) else { return false }
                    // Exception must be deeper than the immutable root (never the root itself).
                    guard let root = immutableRefuseRoot(matchingLowerPath: lowerException) else { return false }
                    return lowerException != root.lowercased() && lowerException.hasPrefix(root.lowercased() + "/")
                }
                if hasNarrowException {
                    continue
                }
                throw SafetyError.protectedPath(immutableRefuseRoot(matchingLowerPath: lowerP) ?? p)
            }

            // Custom exceptions must never override user personal content roots.
            let isUserContentRoot = homeVariants.contains { h in
                [
                    "\(h)/Documents",
                    "\(h)/Desktop",
                    "\(h)/Downloads",
                    "\(h)/Movies",
                    "\(h)/Music",
                    "\(h)/Pictures",
                    "\(h)/Backups",
                ].contains { NormalizedPath.isEqualOrDescendant(lowerP, of: $0.lowercased()) }
            }

            if policy == .userSelected {
                let isStrictUserContentDescendant = homeVariants.contains { h in
                    [
                        "\(h)/Documents",
                        "\(h)/Desktop",
                        "\(h)/Downloads",
                        "\(h)/Movies",
                        "\(h)/Music",
                        "\(h)/Pictures",
                        "\(h)/Backups",
                    ].contains { lowerP.hasPrefix($0.lowercased() + "/") }
                }
                if isStrictUserContentDescendant {
                    continue
                }
            }

            let isException = !isUserContentRoot && allowedExceptions.contains { exception in
                NormalizedPath.isEqualOrDescendant(lowerP, of: exception.lowercased())
            }

            if isException {
                continue
            }

            // Regenerable project build artifacts / aged backup leaves under user project roots
            if homeVariants.contains(where: {
                Self.isProjectLocalBuildArtifact(p, home: $0)
                    || Self.isReviewableBackupLeaf(p, home: $0)
                    || Self.isReviewableInstallerLeaf(p, home: $0)
                    || Self.isReviewableLargeArchiveLeaf(p, home: $0)
            }) {
                continue
            }

            if Self.isShallowAbsoluteRoot(p) {
                throw SafetyError.protectedPath(p)
            }

            if Self.isAllowedExternalVolumePath(p, policy: policy) {
                continue
            }

            for refused in refuseList {
                let lowerRefused = refused.lowercased()
                let isExactMatch = (lowerP == lowerRefused)
                let isSubdirectory = (lowerRefused == "/")
                    ? (!homeVariants.contains { lowerP.hasPrefix($0.lowercased() + "/") } && lowerP != "/" && lowerP.hasPrefix("/"))
                    : lowerP.hasPrefix(lowerRefused + "/")

                if isExactMatch {
                    throw SafetyError.protectedPath(refused)
                }

                guard isSubdirectory else { continue }

                if lowerRefused == "/applications" && policy.isUninstall {
                    continue
                }

                throw SafetyError.protectedPath(refused)
            }
        }
    }

    /// True for paths inside (or being) a browser user-data root — logins, cookies, profiles.
    public func isBrowserUserDataPath(_ path: String) -> Bool {
        let stdLower = NormalizedPath.lowercaseKey(path)
        let resolvedLower = NormalizedPath.resolvedLowercaseKey(path)
        return browserSpecs.contains { spec in
            NormalizedPath.isEqualOrDescendant(stdLower, of: spec.lowerRoot)
                || NormalizedPath.isEqualOrDescendant(resolvedLower, of: spec.lowerRoot)
        }
    }

    /// True if uninstalling `bundleID` must not touch `path` because it is a browser user-data
    /// root (or ancestor) owned by another browser or protected by the system.
    public func isProtectedBrowserTarget(_ path: String, uninstallingBundleID bundleID: String?) -> Bool {
        let std = NormalizedPath.string(URL(fileURLWithPath: path).standardizedFileURL.path)
        let resolved = NormalizedPath.resolvedString(std)
        let policy = DeletionPolicy.uninstallApp(bundleID: bundleID)
        for candidate in [std, resolved] {
            if browserProtectedPath(candidate, lowerP: candidate.lowercased(), policy: policy) != nil {
                return true
            }
        }
        return false
    }

    /// Whether a directory URL is a symlink and must not be traversed into.
    public func isSymlinkDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return isSymlink(at: url)
    }

    private static let protectedExternalVolumeNames: Set<String> = [
        "recovery", "preboot", "vm", "update", "iscpreboot", "xarts",
        "hardware", "base system", "macos base system", "timemachine",
    ]
    private static let protectedExternalVolumeSegments: Set<String> = [
        ".spotlight-v100", ".fseventsd", ".documentrevisions-v100",
        ".trashes", ".temporaryitems", "backups.backupdb", ".vol", ".mobilebackups",
    ]
    private static let protectedExternalTopLevelDirs: Set<String> = [
        "system", "usr", "bin", "sbin", "private", "etc", "var", "dev", "cores",
    ]

    /// True if `volumeName` is a safe user-accessible mounted external volume (not hidden, system, or Time Machine).
    public static func isAllowedExternalVolumeName(_ volumeName: String) -> Bool {
        let trimmed = volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(".") else { return false }
        let lower = trimmed.lowercased()
        if protectedExternalVolumeNames.contains(lower) { return false }
        if lower.contains("timemachine") || lower.contains("time machine") || lower.contains("backups.backupdb") {
            return false
        }
        return true
    }

    /// Allows explicit user-driven operations (`.uninstall`, `.uninstallApp`, `.userSelected`)
    /// on files/apps inside a mounted non-root external volume (`/Volumes/<Disk>/<child>`).
    /// Automated `.cleanup` never operates on external volumes, and `/Volumes` or `/Volumes/<Disk>`
    /// mount roots themselves are always refused.
    public static func isAllowedExternalVolumePath(_ path: String, policy: DeletionPolicy) -> Bool {
        guard policy.isUninstall || policy == .userSelected else { return false }
        let normalized = NormalizedPath.string(URL(fileURLWithPath: path).standardizedFileURL.path)
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 3, components[0].lowercased() == "volumes" else { return false }

        let volumeName = components[1]
        guard isAllowedExternalVolumeName(volumeName) else { return false }

        let lowerComponents = components.dropFirst(2).map { $0.lowercased() }
        if let top = lowerComponents.first, protectedExternalTopLevelDirs.contains(top) {
            return false
        }
        if lowerComponents.contains(where: { protectedExternalVolumeSegments.contains($0) }) {
            return false
        }
        let lowerPath = normalized.lowercased()
        if lowerPath.contains("/library/application support/apple")
            || lowerPath.contains("/library/application support/com.apple.tcc") {
            return false
        }
        return true
    }

    private func browserProtectedPath(_ path: String, lowerP: String, policy: DeletionPolicy) -> String? {
        // Strict ancestors of any browser root (e.g. ~/Library/Application Support/Google)
        // must never be deleted wholesale under any policy.
        for spec in browserSpecs where NormalizedPath.isStrictAncestor(lowerP, of: spec.lowerRoot) {
            return path
        }

        // Check most specific matching spec (longest root wins if any overlap exists).
        let matchingSpecs = browserSpecs
            .filter { NormalizedPath.isEqualOrDescendant(lowerP, of: $0.lowerRoot) }
            .sorted { $0.lowerRoot.count > $1.lowerRoot.count }

        guard let spec = matchingSpecs.first else {
            return nil
        }

        switch policy {
        case .cleanup:
            if lowerP == spec.lowerRoot {
                return spec.canonicalRoot
            }
            return isAllowedBrowserCachePath(spec: spec, lowerP: lowerP) ? nil : path

        case .uninstall:
            // Generic uninstall without an owning app bundleID must never touch browser profiles.
            return spec.canonicalRoot

        case .uninstallApp(let bundleID):
            guard !spec.isSystemProtected else {
                return spec.canonicalRoot
            }
            guard let rawBundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawBundleID.isEmpty,
                  !BrowserRule.isBrowserPWAShimBundleID(rawBundleID)
            else {
                return spec.canonicalRoot
            }
            return spec.ownerBundleIDs.contains(rawBundleID.lowercased()) ? nil : spec.canonicalRoot

        case .userSelected:
            return spec.isSystemProtected ? spec.canonicalRoot : nil
        }
    }

    private func isAllowedBrowserCachePath(spec: BrowserRootSpec, lowerP: String) -> Bool {
        let relPath = String(lowerP.dropFirst(spec.lowerRoot.count))
        let components = relPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return false }

        if components.contains(where: { Self.browserProtectedSegments.contains($0) }) {
            return false
        }

        switch spec.layout {
        case .opaqueUserData:
            if spec.isSystemProtected {
                return false
            }
            return components[0] == "crashpad"

        case .safariLibrary:
            return Self.safariLibraryCacheDirs.contains(components[0])

        case .browserContainer:
            if components.count >= 3,
               components[0] == "data",
               components[1] == "library",
               (components[2] == "caches" || components[2] == "logs") {
                return true
            }
            if components.count >= 2,
               components[0] == "data",
               components[1] == "tmp" {
                return true
            }
            return false

        case .firefox:
            if components[0] == "crashpad" {
                return true
            }
            let idx = components[0] == "firefox" ? 1 : 0
            guard components.count >= idx + 3 else { return false }
            guard components[idx] == "profiles" else { return false }
            return Self.firefoxProfileCacheDirs.contains(components[idx + 2])

        case .chromium(let channelSubdirs):
            let startIdx = channelSubdirs.contains(components[0]) ? 1 : 0
            guard components.count > startIdx else { return false }

            if Self.chromiumRootCacheDirs.contains(components[startIdx]) {
                return true
            }

            guard components.count >= startIdx + 2 else { return false }
            let profile = components[startIdx]
            guard Self.isChromiumProfileDirName(profile) else { return false }

            let dir = components[startIdx + 1]
            if Self.chromiumProfileCacheDirs.contains(dir) {
                return true
            }
            if dir == "service worker", components.count >= startIdx + 3 {
                return components[startIdx + 2] == "cachestorage" || components[startIdx + 2] == "scriptcache"
            }
            return false
        }
    }

    private static func isChromiumProfileDirName(_ lowerName: String) -> Bool {
        lowerName == "default"
            || lowerName == "guest profile"
            || lowerName == "system profile"
            || lowerName.hasPrefix("profile ")
    }

    private func isUnderImmutableRefuseRoot(_ lowerPath: String) -> Bool {
        immutableRefuseRoots.contains {
            NormalizedPath.isEqualOrDescendant(lowerPath, of: $0.lowercased())
        }
    }

    private func immutableRefuseRoot(matchingLowerPath lowerPath: String) -> String? {
        immutableRefuseRoots.first {
            NormalizedPath.isEqualOrDescendant(lowerPath, of: $0.lowercased())
        }
    }

    /// Walk each path component; intermediate symlink directories that escape are refused.
    /// Darwin path aliases (`/var`, `/tmp`, `/etc`) are always allowed as intermediates.
    private func validateSymlinkComponents(of url: URL) throws {
        let path = url.path
        guard path.hasPrefix("/") else { return }

        let fullyResolved = url.resolvingSymlinksInPath().path
        let darwinAliases: Set<String> = ["/var", "/tmp", "/etc"]
        var accumulated = ""
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        for (index, component) in components.enumerated() {
            accumulated += "/" + component
            let componentURL = URL(fileURLWithPath: accumulated)
            guard isSymlink(at: componentURL) else { continue }

            let isLeaf = index == components.count - 1
            if isLeaf {
                continue
            }

            if darwinAliases.contains(accumulated) {
                continue
            }

            let resolvedComponent = componentURL.resolvingSymlinksInPath().path
            let stillOnPath = fullyResolved == resolvedComponent
                || fullyResolved.hasPrefix(resolvedComponent + "/")
            if stillOnPath {
                continue
            }
            throw SafetyError.symlinkEscapeAttempted
        }
    }

    private func isSymlink(at url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            return true
        }
        var st = stat()
        let result = lstat(url.path, &st)
        guard result == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    private func cleanupProtectedPath(_ path: String, lowerPath: String) -> String? {
        // Protect Mail wholesale during cleanup (never touch attachments or mailbox databases)
        for h in homeVariants {
            let lowerMail = "\(h.lowercased())/library/mail"
            if NormalizedPath.isEqualOrDescendant(lowerPath, of: lowerMail) {
                return "\(h)/Library/Mail"
            }
        }

        // Project settings and IDE configurations (e.g. .vscode, .idea, .zed)
        if lowerPath.contains("/.vscode/") || lowerPath.hasSuffix("/.vscode")
            || lowerPath.contains("/.idea/") || lowerPath.hasSuffix("/.idea")
            || lowerPath.contains("/.zed/") || lowerPath.hasSuffix("/.zed") {
            return path
        }

        // Shared file lists (Finder sidebar favorites, etc.)
        if lowerPath.contains("/com.apple.sharedfilelist/") {
            let sflName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            let safeSFLNames: Set<String> = [
                "com.apple.lssharedfilelist.recentdocuments.sfl3",
                "com.apple.lssharedfilelist.recentapplications.sfl3",
                "com.apple.lssharedfilelist.recentservers.sfl3",
                "com.apple.lssharedfilelist.recenthosts.sfl3",
                "com.apple.lssharedfilelist.recentdocuments.sfl4",
                "com.apple.lssharedfilelist.recentapplications.sfl4",
                "com.apple.lssharedfilelist.recentservers.sfl4",
                "com.apple.lssharedfilelist.recenthosts.sfl4",
            ]
            if !safeSFLNames.contains(sflName) {
                return path
            }
        }

        // IDE user configuration (VS Code, Cursor, Windsurf, Zed, etc.)
        let protectedIDEParents = [
            "/application support/code/user/",
            "/application support/code - insiders/user/",
            "/application support/cursor/user/",
            "/application support/windsurf/user/",
            "/application support/ai.opencode.desktop/user/",
            "/.config/zed/",
            "/application support/dev.zed.zed/",
        ]
        if protectedIDEParents.contains(where: { lowerPath.contains($0) }) {
            // Under User/, only workspaceStorage and explicit AI extension caches are cleanable;
            // settings, keybindings, snippets remain protected.
            let isWorkspaceStorage = lowerPath.contains("/user/workspacestorage/") || lowerPath.hasSuffix("/user/workspacestorage")
            let isExtensionCache = lowerPath.contains("/user/globalstorage/saoudrizwan.claude-dev/cache")
                || lowerPath.contains("/user/globalstorage/rooveterinaryinc.roo-cline/cache")
            if !isWorkspaceStorage && !isExtensionCache {
                return path
            }
        }

        // Project / IDE configuration files anywhere (e.g. settings.json, launch.json, tasks.json)
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let protectedConfigFiles: Set<String> = [
            "settings.json", "launch.json", "tasks.json",
            "extensions.json", "keybindings.json",
            ".env", "credentials", "credentials.toml",
            ".npmrc", ".yarnrc", ".pypirc",
            "gradle.properties", "settings.xml", ".claude.json",
        ]
        if protectedConfigFiles.contains(fileName) || fileName.hasPrefix(".env.") {
            return path
        }

        // Credential and cookie files across Library, Application Support, and Containers
        var basename = fileName
        for suffix in ["-journal", "-wal", "-shm"] where basename.hasSuffix(suffix) {
            basename = String(basename.dropLast(suffix.count))
            break
        }
        return credentialFileNames.contains(basename) ? path : nil
    }

    static func isShallowAbsoluteRoot(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path != "/" else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.count <= 1
    }

    /// True when `path` matches a known regenerable dot-cache template from `EmbeddedCleanupPaths`.
    public static func isRegenerableCachePath(_ path: String, home: String) -> Bool {
        let stdHome = NormalizedPath.string(URL(fileURLWithPath: home).standardizedFileURL.path)
        let resolvedHome = NormalizedPath.resolvedString(stdHome)
        let variants = resolvedHome == stdHome ? [stdHome] : [stdHome, resolvedHome]
        return isRegenerableCachePath(path, homeVariants: variants)
    }

    private static func isRegenerableCachePath(_ path: String, homeVariants: [String]) -> Bool {
        let lowerPath = NormalizedPath.lowercaseKey(path)
        for h in homeVariants {
            let baseHome = h.hasSuffix("/") ? String(h.dropLast()) : h
            for template in EmbeddedCleanupPaths.regenerableDotCacheTemplates() {
                let resolved = template.hasPrefix("~") ? baseHome + template.dropFirst() : template
                let lowerTarget = NormalizedPath.lowercaseKey(resolved)
                if NormalizedPath.isEqualOrDescendant(lowerPath, of: lowerTarget) {
                    return true
                }
            }
        }
        return false
    }

    private static func isReviewableAIModelPath(_ path: String, homeVariants: [String]) -> Bool {
        let lowerPath = NormalizedPath.lowercaseKey(path)
        for h in homeVariants {
            let baseHome = h.hasSuffix("/") ? String(h.dropLast()) : h
            for template in GeneratedCleanupPaths.aiUserContentTemplates() {
                let resolved = PathToken.home.resolveTemplate(template, home: baseHome)
                let lowerTarget = NormalizedPath.lowercaseKey(resolved)
                if NormalizedPath.isEqualOrDescendant(lowerPath, of: lowerTarget) {
                    return true
                }
            }
        }
        return false
    }

    /// Regenerable build/cache dirs under common project roots.
    static func isProjectLocalBuildArtifact(_ path: String, home: String) -> Bool {
        ProjectArtifactRules.isArtifact(
            at: URL(fileURLWithPath: path).standardizedFileURL,
            home: home
        )
    }

    /// Direct children of Desktop/Documents/Downloads that look like aged backups.
    /// Never allows `~/Backups` or arbitrary nested user content.
    static func isReviewableBackupLeaf(_ path: String, home: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        let parentLower = standardized.deletingLastPathComponent().path.lowercased()
        let allowedParents = [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
        ].map { NormalizedPath.lowercaseKey($0) }
        guard allowedParents.contains(parentLower) else { return false }

        let name = standardized.lastPathComponent.lowercased()
        return name.hasSuffix(".backup")
            || name.hasSuffix(".bak")
            || name.hasSuffix(".old")
            || name.hasSuffix("~")
    }

    /// Installer images (DMG/PKG/ISO) from user folders, Homebrew downloads, or messenger downloads,
    /// plus installer `.zip` archives under Desktop/Documents/Downloads.
    static func isReviewableInstallerLeaf(_ path: String, home: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        let name = standardized.lastPathComponent.lowercased()
        let isImage = name.hasSuffix(".dmg") || name.hasSuffix(".pkg") || name.hasSuffix(".iso")
        if Self.reviewableDownloadLeafName(path, home: home) != nil {
            if isImage { return true }
            if name.hasSuffix(".zip") {
                return ZipCentralDirectoryInspector.containsInstallerPayload(at: standardized.path)
            }
            return false
        }
        guard isImage else { return false }
        return Self.isMessengerOrHomebrewInstallerPath(standardized.path, home: home)
    }

    /// Top-level large archives under Desktop/Documents/Downloads (opt-in cleanup).
    static func isReviewableLargeArchiveLeaf(_ path: String, home: String) -> Bool {
        guard let name = Self.reviewableDownloadLeafName(path, home: home) else { return false }
        return name.hasSuffix(".zip")
            || name.hasSuffix(".rar")
            || name.hasSuffix(".7z")
            || name.hasSuffix(".tar")
            || name.hasSuffix(".gz")
            || name.hasSuffix(".tgz")
    }

    private static func reviewableDownloadLeafName(_ path: String, home: String) -> String? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        let parentLower = standardized.deletingLastPathComponent().path.lowercased()
        let allowedParents = [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
        ].map { NormalizedPath.lowercaseKey($0) }
        guard allowedParents.contains(parentLower) else { return nil }
        return standardized.lastPathComponent.lowercased()
    }

    private static func isMessengerOrHomebrewInstallerPath(_ standardizedPath: String, home: String) -> Bool {
        let baseHome = URL(fileURLWithPath: home).standardizedFileURL.path
        let parentLower = URL(fileURLWithPath: standardizedPath).deletingLastPathComponent().path.lowercased()
        let exactDownloadDirs: Set<String> = Set([
            "\(baseHome)/Library/Caches/Homebrew/downloads",
            "\(baseHome)/Library/Application Support/Slack/Downloads",
            "\(baseHome)/Library/Containers/com.tinyspeck.slackmacgap/Data/Downloads",
            "\(baseHome)/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/Downloads",
            "\(baseHome)/Library/Application Support/discord/Downloads",
            "\(baseHome)/Library/Containers/net.whatsapp.WhatsApp/Data/Downloads",
            "\(baseHome)/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Application Support/WhatsApp/Downloads",
            "\(baseHome)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media",
        ].map { $0.lowercased() })
        if exactDownloadDirs.contains(parentLower) {
            return true
        }
        let telegramRoot = "\(baseHome)/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/".lowercased()
        if parentLower.hasPrefix(telegramRoot) && parentLower.hasSuffix("/postbox/media") {
            return true
        }
        return false
    }

    private static func dedupePreservingOrder(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }
}
