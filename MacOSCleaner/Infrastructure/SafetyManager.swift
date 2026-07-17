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
    private let refuseList: [String]
    private let allowedExceptions: [String]

    // OS-owned dirs living inside allowed exception roots (e.g. /Library/Application Support).
    // Checked before exceptions, so they can never be deleted.
    private let hardRefuseList: [String]

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

    public init(allowedExceptions: [String] = []) {
        let home = NSHomeDirectory()
        self.refuseList = [
            "/",
            "/System",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/private",
            "/etc",
            "/var",
            "/tmp",
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/Documents",
        ]
        
        let defaultExceptions = [
            "\(home)/Library",
            "/Library/Application Support",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Receipts",
            "/Library/Internet Plug-Ins",
            "/private/var/folders",
            "/private/tmp",
            "/tmp",
            "/usr/local",
            "\(home)/Library/Application Support/MacOSCleaner",
            "\(home)/Library/Application Scripts/input.MacOSCleaner",
            // Safe cache directories
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
            "\(home)/.android",
            "\(home)/Library/Android",
            // Browser caches (safe to clean)
            "\(home)/Library/Safari",
            "\(home)/Library/WebKit",
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Chrome",
        ]
        
        self.allowedExceptions = defaultExceptions + allowedExceptions

        self.hardRefuseList = [
            "/Library/Application Support/Apple",
            "/Library/Application Support/Script Editor",
            "\(home)/Library/Application Support/Apple",
            // Sensitive user data — protected even inside allowed exception roots.
            // Mail paths are intentionally absent: cleanup legitimately clears
            // attachment caches there; the uninstaller filters Mail on its side.
            "\(home)/Library/Keychains",
            "\(home)/Library/Calendars",
            "\(home)/Library/Reminders",
            "\(home)/Library/Contacts",
            "\(home)/Library/Application Support/AddressBook",
            // Passwords and credentials
            "\(home)/Library/Application Support/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Chrome/Default/Cookies",
            "\(home)/Library/Application Support/Google/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Google/Chrome/Default/Cookies",
            // TCC / system integrity (cleanup.json never_delete)
            "\(home)/Library/Application Support/com.apple.TCC",
            "/Library/Application Support/com.apple.TCC",
            "/var/db/dslocal",
            "/private/var/db/dslocal",
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
            "shadercache", "grshadercache", "crashpad", "service worker",
            // Firefox profile caches
            "cache2", "startupcache", "thumbnails",
        ]
        self.credentialFileNames = [
            "login data", "login data for account", "cookies",
            "web data", "account web data", "local state", "secure preferences",
        ]

        // Note: roots whose *contents* cleanup legitimately clears (Saved Application
        // State, ~/Library/LaunchAgents, /Library/LaunchDaemons) are not listed —
        // FileCleanupActor validates the root itself before touching children.
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
            "/Library/Application Support",
            "/Library/Preferences",
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

        let resolvedPath = standardized.resolvingSymlinksInPath().path

        let pathsToCheck = [path, resolvedPath]
        
        for p in pathsToCheck {
            for refused in hardRefuseList where p == refused || p.hasPrefix(refused + "/") {
                throw SafetyError.protectedPath(refused)
            }

            if exactRefuseList.contains(p) {
                throw SafetyError.protectedPath(p)
            }

            if policy == .cleanup, let refused = cleanupProtectedPath(p) {
                throw SafetyError.protectedPath(refused)
            }

            let isException = allowedExceptions.contains { exception in
                p == exception || p.hasPrefix(exception + "/")
            }
            
            if isException {
                continue
            }

            // VM disk images / user containers under Documents or Desktop — app residuals only
            if Self.isVirtualizationUserDataResidual(p) {
                continue
            }

            for refused in refuseList {
                let isExactMatch = (p == refused)
                let isSubdirectory = p.hasPrefix(refused + "/")
                
                if isExactMatch || isSubdirectory {
                    throw SafetyError.protectedPath(refused)
                }
            }
        }
    }

    /// True for paths inside (or being) a browser user-data root — logins, cookies, profiles.
    public func isBrowserUserDataPath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return browserUserDataRoots.contains { standardized == $0 || standardized.hasPrefix($0 + "/") }
    }

    /// Cleanup-only protection: login/session data survives regular cleanup.
    /// Returns the path that must be protected, or nil when deletion is allowed.
    private func cleanupProtectedPath(_ path: String) -> String? {
        for root in browserUserDataRoots {
            // The root itself, or an ancestor directory whose removal would take
            // the root with it (e.g. ~/Library/Application Support/Google).
            if path == root || root.hasPrefix(path + "/") {
                return path
            }
            guard path.hasPrefix(root + "/") else { continue }
            let components = path.dropFirst(root.count + 1)
                .split(separator: "/")
                .map { $0.lowercased() }
            if components.contains(where: { browserCacheDirNames.contains($0) }) {
                return nil
            }
            return path
        }

        // Credential/session files of any app under Application Support
        // (Electron and Chromium-based apps share the same file names).
        guard path.contains("/Application Support/") else { return nil }
        var basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        for suffix in ["-journal", "-wal", "-shm"] where basename.hasSuffix(suffix) {
            basename = String(basename.dropLast(suffix.count))
            break
        }
        return credentialFileNames.contains(basename) ? path : nil
    }

    /// Allows deletion of VM/container user data under Documents or Desktop when clearly app-owned.
    static func isVirtualizationUserDataResidual(_ path: String) -> Bool {
        let home = NSHomeDirectory().lowercased()
        let lower = path.lowercased()
        guard lower.hasPrefix("\(home)/documents/")
            || lower.hasPrefix("\(home)/desktop/") else { return false }
        let vmMarkers = [
            "orbstack", "parallels", "vmware", "virtualbox", "utm",
            "virtual machines", ".pvm", ".vmx", ".vmdk", ".qcow2",
        ]
        return vmMarkers.contains { lower.contains($0) }
    }
}
