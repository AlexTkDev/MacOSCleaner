import Foundation

public enum SafetyError: Error, Equatable {
    case pathNormalizationFailed
    case symlinkEscapeAttempted
    case protectedPath(String)
}

/// Context of a deletion request. Regular cleanup must never touch login/session
/// data; a full app uninstall is allowed to remove the app's user data.
public enum DeletionPolicy: Sendable {
    case cleanup
    case uninstall
}

public struct SafetyManager: Sendable {
    private let home: String
    private let refuseList: [String]
    private let allowedExceptions: [String]

    // OS-owned dirs living inside allowed exception roots (e.g. /Library/Application Support).
    // Checked before exceptions, so they can never be deleted.
    private let hardRefuseList: [String]

    // Roots that custom exceptions must never override.
    private let immutableRefuseRoots: [String]

    // Directories that must never be deleted wholesale, though their children may be
    // (e.g. ~/Library/Preferences itself vs. an app's plist inside it). Exact match only.
    private let exactRefuseList: Set<String>

    // Browser user-data roots holding logins, cookies and site sessions.
    // Under .cleanup only well-known cache subdirectories inside them may be deleted.
    private let browserUserDataRoots: [String]

    // Lowercased directory names inside browser user-data roots that are safe caches.
    private let browserCacheDirNames: Set<String>

    // Lowercased basenames of credential/session files (Chromium family) protected
    // anywhere under Application Support during cleanup.
    private let credentialFileNames: Set<String>

    private let fileSystemContext: FileSystemContext?

    public init(allowedExceptions: [String] = [], homeDirectory: String? = nil, fileSystemContext: FileSystemContext? = nil) {
        let home = homeDirectory
            ?? fileSystemContext?.homePath
            ?? NSHomeDirectory()
        self.home = home
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

        self.refuseList = [
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
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Downloads",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Pictures",
            "\(home)/Backups",
            "/",
        ]

        let defaultExceptions = [
            "\(home)/Library",
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
            "\(home)/Library/Application Support/MacOSCleaner",
            "\(home)/Library/Application Scripts/input.MacOSCleaner",
            "\(home)/Library/Caches",
            "\(home)/Library/Developer",
            "\(home)/Library/Logs",
            "\(home)/Library/Application Support",
            "\(home)/Library/Containers",
            "\(home)/.cache",
            "\(home)/.config",
            "\(home)/.local",
            "\(home)/.gradle",
            "\(home)/.pub-cache",
            "\(home)/.dartServer",
            "\(home)/.swiftpm/cache",
            "\(home)/.cocoapods/repos",
            "\(home)/.kotlin",
            "\(home)/.flutter-devtools",
            "\(home)/.m2",
            "\(home)/.android",
            "\(home)/.ollama",
            "\(home)/.diffusionbee",
            "\(home)/jan",
            "\(home)/Library/Android",
            "\(home)/Library/Safari",
            "\(home)/Library/WebKit",
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Chrome",
            "/opt/homebrew/Cellar",
            "/opt/homebrew/Caskroom",
            "/usr/local/Cellar",
            "/usr/local/Caskroom",
            URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path,
            URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL.path,
        ]

        self.allowedExceptions = defaultExceptions + allowedExceptions

        self.hardRefuseList = [
            "/Library/Application Support/Apple",
            "/Library/Application Support/Script Editor",
            "\(home)/Library/Application Support/Apple",
            "\(home)/Library/Keychains",
            "\(home)/Library/Calendars",
            "\(home)/Library/Reminders",
            "\(home)/Library/Contacts",
            "\(home)/Library/Application Support/AddressBook",
            "\(home)/Library/Messages",
            "\(home)/Library/Mobile Documents",
            "\(home)/Library/Preferences/com.google.Keystone.Agent.plist",
            "\(home)/Library/Google/GoogleSoftwareUpdate",
            "\(home)/Library/Application Support/Google/GoogleUpdater",
            "\(home)/Library/Caches/com.google.SoftwareUpdate",
            "\(home)/Library/Caches/com.google.GoogleUpdater",
            "\(home)/Library/HTTPStorages/com.google.GoogleUpdater",
            "\(home)/Library/LaunchAgents/com.google.keystone.agent.plist",
            "\(home)/Library/LaunchAgents/com.google.keystone.xpcservice.plist",
            "\(home)/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist",
            "\(home)/Library/Application Support/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Chrome/Default/Cookies",
            "\(home)/Library/Application Support/Google/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Google/Chrome/Default/Cookies",
            "\(home)/Library/Application Support/com.apple.TCC",
            "/Library/Application Support/com.apple.TCC",
            "/var/db/dslocal",
            "/private/var/db/dslocal",
            // Sensitive user credentials roots
            "\(home)/.ssh",
            "\(home)/.gnupg",
        ]

        let appSupport = "\(home)/Library/Application Support"
        self.browserUserDataRoots = [
            "\(appSupport)/Google/Chrome",
            "\(appSupport)/Google/Chrome Beta",
            "\(appSupport)/Google/Chrome Canary",
            "\(appSupport)/Google/Chrome Dev",
            "\(appSupport)/Chrome",
            "\(appSupport)/Chromium",
            "\(appSupport)/BraveSoftware",
            "\(appSupport)/Microsoft Edge",
            "\(appSupport)/Microsoft Edge Beta",
            "\(appSupport)/Microsoft Edge Canary",
            "\(appSupport)/Microsoft Edge Dev",
            "\(appSupport)/Arc/User Data",
            "\(appSupport)/Firefox/Profiles",
            "\(appSupport)/Vivaldi",
            "\(appSupport)/Yandex/YandexBrowser",
            "\(appSupport)/com.operasoftware.Opera",
            "\(appSupport)/com.operasoftware.OperaGX",
            "\(appSupport)/com.operasoftware.OperaDeveloperEdition",
        ]
        self.browserCacheDirNames = [
            "cache", "code cache", "gpucache",
            "shadercache", "grshadercache", "crashpad",
            // Narrow Service Worker: only CacheStorage / ScriptCache are regenerable caches.
            "cachestorage", "scriptcache",
            "cache2", "startupcache", "thumbnails",
        ]
        self.credentialFileNames = [
            "login data", "login data for account", "cookies",
            "web data", "account web data", "local state", "secure preferences",
            "cookies.sqlite", "cookies.binarycookies",
            "logins.json", "key4.db", "cert9.db",
            "places.sqlite", "favicons.sqlite", "formhistory.sqlite",
            "sessionstore.jsonlz4", "logins-backup.json",
        ]

        self.exactRefuseList = [
            "/Users",
            home,
            "\(home)/Library",
            "\(home)/Library/Preferences",
            "\(home)/Library/Preferences/ByHost",
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Logs",
            "\(home)/Library/WebKit",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Developer",
            "\(home)/Library/Messages",
            "\(home)/Library/Mobile Documents",
            "\(home)/Library/Cookies",
            "\(home)/Backups",
            "/Library/Application Support",
            "/Library/Preferences",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/PrivilegedHelperTools",
            "\(home)/Library/LaunchAgents",
            "/tmp",
            "/private/tmp",
            URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path,
            URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL.path,
        ]
    }

    public func validate(url: URL, policy: DeletionPolicy = .cleanup) throws {
        guard url.isFileURL else {
            throw SafetyError.pathNormalizationFailed
        }

        let standardized = url.standardizedFileURL
        let path = standardized.path

        guard !path.isEmpty else {
            throw SafetyError.pathNormalizationFailed
        }

        if let ctx = fileSystemContext {
            try ctx.assertAllowedForMutation(standardized)
        }

        try validateSymlinkComponents(of: standardized)

        let resolvedPath = standardized.resolvingSymlinksInPath().path
        let pathsToCheck = [path, resolvedPath]

        for p in pathsToCheck {
            for refused in hardRefuseList where p == refused || p.hasPrefix(refused + "/") {
                throw SafetyError.protectedPath(refused)
            }

            // Apple system group containers must never be removed
            if p == "\(home)/Library/Group Containers" {
                throw SafetyError.protectedPath(p)
            }
            if p.hasPrefix("\(home)/Library/Group Containers/group.com.apple")
                || p.hasPrefix("\(home)/Library/Group Containers/com.apple") {
                throw SafetyError.protectedPath("\(home)/Library/Group Containers")
            }

            if exactRefuseList.contains(p) {
                throw SafetyError.protectedPath(p)
            }

            // Protect ~/Library/Mail under uninstall unless inside ~/Library/Mail/Bundles
            if policy == .uninstall && (p == "\(home)/Library/Mail" || p.hasPrefix("\(home)/Library/Mail/")) {
                let bundles = "\(home)/Library/Mail/Bundles"
                if !(p == bundles || p.hasPrefix(bundles + "/")) {
                    throw SafetyError.protectedPath("\(home)/Library/Mail")
                }
            }

            if policy == .cleanup, let refused = cleanupProtectedPath(p) {
                throw SafetyError.protectedPath(refused)
            }

            // Custom exceptions never override immutable system / shared roots themselves.
            // Only pre-declared narrow subpaths (Homebrew Cellar, /Library/LaunchAgents, …) may pass.
            if isUnderImmutableRefuseRoot(p) {
                if p == "/Applications" || p.hasPrefix("/Applications/") {
                    if policy == .uninstall, p != "/Applications" {
                        continue
                    }
                    throw SafetyError.protectedPath("/Applications")
                }

                let hasNarrowException = allowedExceptions.contains { exception in
                    guard p == exception || p.hasPrefix(exception + "/") else { return false }
                    // Exception must be deeper than the immutable root (never the root itself).
                    guard let root = immutableRefuseRoot(matching: exception) else { return false }
                    return exception != root && exception.hasPrefix(root + "/")
                }
                if hasNarrowException {
                    continue
                }
                throw SafetyError.protectedPath(immutableRefuseRoot(matching: p) ?? p)
            }

            // Custom exceptions must never override user personal content roots.
            let isUserContentRoot = [
                "\(home)/Documents",
                "\(home)/Desktop",
                "\(home)/Downloads",
                "\(home)/Movies",
                "\(home)/Music",
                "\(home)/Pictures",
                "\(home)/Backups",
            ].contains { p == $0 || p.hasPrefix($0 + "/") }

            let isException = !isUserContentRoot && allowedExceptions.contains { exception in
                p == exception || p.hasPrefix(exception + "/")
            }

            if isException {
                continue
            }

            // Regenerable project build artifacts / aged backup leaves under user project roots
            if Self.isProjectLocalBuildArtifact(p, home: home)
                || Self.isReviewableBackupLeaf(p, home: home)
                || Self.isReviewableInstallerLeaf(p, home: home)
                || Self.isReviewableLargeArchiveLeaf(p, home: home) {
                continue
            }

            if Self.isShallowAbsoluteRoot(p) {
                throw SafetyError.protectedPath(p)
            }

            for refused in refuseList {
                let isExactMatch = (p == refused)
                let isSubdirectory = (refused == "/")
                    ? (!p.hasPrefix(home + "/") && p != "/" && p.hasPrefix("/"))
                    : p.hasPrefix(refused + "/")

                if isExactMatch {
                    throw SafetyError.protectedPath(refused)
                }

                guard isSubdirectory else { continue }

                if refused == "/Applications" && policy == .uninstall {
                    continue
                }

                throw SafetyError.protectedPath(refused)
            }
        }
    }

    /// True for paths inside (or being) a browser user-data root — logins, cookies, profiles.
    public func isBrowserUserDataPath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return browserUserDataRoots.contains { standardized == $0 || standardized.hasPrefix($0 + "/") }
    }

    /// Whether a directory URL is a symlink and must not be traversed into.
    public func isSymlinkDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return isSymlink(at: url)
    }

    /// Leaf symlink: operate on the link itself, never follow to the target.
    public func isLeafSymlink(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists, !isDir.boolValue else { return false }
        return isSymlink(at: url)
    }

    private func isUnderImmutableRefuseRoot(_ path: String) -> Bool {
        immutableRefuseRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func immutableRefuseRoot(matching path: String) -> String? {
        immutableRefuseRoots.first { path == $0 || path.hasPrefix($0 + "/") }
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

    private func cleanupProtectedPath(_ path: String) -> String? {
        let lowerPath = path.lowercased()

        // Protect Mail wholesale during cleanup (never touch attachments or mailbox databases)
        if lowerPath == "\(home.lowercased())/library/mail" || lowerPath.hasPrefix("\(home.lowercased())/library/mail/") {
            return "\(home)/Library/Mail"
        }

        for root in browserUserDataRoots {
            if path == root || root.hasPrefix(path + "/") {
                return path
            }
            guard path.hasPrefix(root + "/") else { continue }
            let components = path.dropFirst(root.count + 1)
                .split(separator: "/")
                .map { $0.lowercased() }
            // Only CacheStorage / ScriptCache under Service Worker, not registration/state.
            if components.contains("service worker") {
                if components.contains("cachestorage") || components.contains("scriptcache") {
                    return nil
                }
                return path
            }
            if components.contains(where: { browserCacheDirNames.contains($0) }) {
                return nil
            }
            return path
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
            // Under User/, only workspaceStorage is a cleanable cache; settings, keybindings, snippets are protected
            if !lowerPath.contains("/user/workspacestorage/") && !lowerPath.hasSuffix("/user/workspacestorage") {
                return path
            }
        }

        // Project / IDE configuration files anywhere (e.g. settings.json, launch.json, tasks.json)
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let protectedConfigFiles: Set<String> = [
            "settings.json", "launch.json", "tasks.json",
            "extensions.json", "keybindings.json",
        ]
        if protectedConfigFiles.contains(fileName) {
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

    /// Regenerable build/cache dirs under common project roots.
    static func isProjectLocalBuildArtifact(_ path: String, home: String) -> Bool {
        let homeLower = home.lowercased()
        let lower = path.lowercased()
        let roots = [
            "\(homeLower)/documents/", "\(homeLower)/desktop/", "\(homeLower)/developer/",
            "\(homeLower)/projects/", "\(homeLower)/repos/", "\(homeLower)/src/",
            "\(homeLower)/workspace/", "\(homeLower)/code/",
        ]
        guard let matchingRoot = roots.first(where: { lower.hasPrefix($0) }) else { return false }
        if lower.contains("/.vscode") || lower.contains("/.idea") || lower.contains("/.zed") { return false }

        // Must be inside a project directory (depth >= 2 under Documents or Desktop)
        // e.g. Documents/my_project/build is allowed, Documents/build directly is not
        if matchingRoot == "\(homeLower)/documents/" || matchingRoot == "\(homeLower)/desktop/" {
            let relative = lower.dropFirst(matchingRoot.count)
            let segments = relative.split(separator: "/", omittingEmptySubsequences: true)
            guard segments.count >= 2 else { return false }
        }

        let name = URL(fileURLWithPath: lower).lastPathComponent
        let artifactNames: Set<String> = [
            "build", ".build", "deriveddata", ".dart_tool", "__pycache__",
            ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox",
            ".next", ".nuxt", ".turbo", ".parcel-cache", ".angular", ".svelte-kit",
            ".gradle", "node_modules",
        ]
        return artifactNames.contains(name)
    }

    /// Direct children of Desktop/Documents/Downloads that look like aged backups.
    /// Never allows `~/Backups` or arbitrary nested user content.
    static func isReviewableBackupLeaf(_ path: String, home: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        let parent = standardized.deletingLastPathComponent().path
        let allowedParents = [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
        ].map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        guard allowedParents.contains(parent) else { return false }

        let name = standardized.lastPathComponent.lowercased()
        return name.hasSuffix(".backup")
            || name.hasSuffix(".bak")
            || name.hasSuffix(".old")
            || name.hasSuffix("~")
    }

    /// Top-level DMG/PKG/ISO under Desktop/Documents/Downloads (opt-in cleanup).
    static func isReviewableInstallerLeaf(_ path: String, home: String) -> Bool {
        guard let name = Self.reviewableDownloadLeafName(path, home: home) else { return false }
        return name.hasSuffix(".dmg") || name.hasSuffix(".pkg") || name.hasSuffix(".iso")
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
        let parent = standardized.deletingLastPathComponent().path
        let allowedParents = [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
        ].map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        guard allowedParents.contains(parent) else { return nil }
        return standardized.lastPathComponent.lowercased()
    }
}
