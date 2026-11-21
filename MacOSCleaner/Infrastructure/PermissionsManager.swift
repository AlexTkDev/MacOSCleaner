import Foundation
import AppKit
import os.log

private extension Logger {
    static let permissions = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macoscleaner", category: "PermissionsManager")
}

/// Manages file system permissions and guides users through granting access.
@Observable
public final class PermissionsManager {
    /// Whether the app has Full Disk Access.
    public private(set) var hasFullDiskAccess = false
    
    /// Whether the guidance panel should be shown.
    public var showGuidance = false
    
    /// Whether the user has dismissed the guidance permanently.
    public private(set) var guidanceDismissed = false

    /// Whether Full Disk Access was ever granted (persisted across launches).
    public private(set) var fdaEverGranted = false

    private let userDefaultsKey = "com.macoscleaner.guidanceDismissed"
    private let fdaGrantedKey = "com.macoscleaner.fdaGranted"
    private let userDefaults: UserDefaults
    private let fdaCheckClosure: @Sendable () -> Bool

    public init(userDefaults: UserDefaults = .standard, fdaCheck: (@Sendable () -> Bool)? = nil) {
        self.userDefaults = userDefaults
        let check = fdaCheck ?? { Self.checkFullDiskAccess() }
        self.fdaCheckClosure = check
        self.guidanceDismissed = userDefaults.bool(forKey: userDefaultsKey)
        self.fdaEverGranted = userDefaults.bool(forKey: fdaGrantedKey)

        let liveFDA = check()
        self.hasFullDiskAccess = liveFDA
        if liveFDA {
            persistFDAState()
        }
    }
    
    /// Target paths guarded by macOS TCC that only succeed when Full Disk Access is granted.
    static func fdaProbeTargets(homeDirectory: String) -> (files: [String], directories: [String]) {
        let files = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            homeDirectory + "/Library/Safari/CloudTabs.db",
            homeDirectory + "/Library/Safari/Bookmarks.plist",
        ]
        let directories = [
            homeDirectory + "/Library/Suggestions",
            homeDirectory + "/Library/Mail",
            homeDirectory + "/Library/Safari",
        ]
        return (files, directories)
    }

    /// Checks if the application has Full Disk Access by attempting to read TCC-protected paths.
    public static func checkFullDiskAccess(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> Bool {
        let fm = FileManager.default
        let targets = fdaProbeTargets(homeDirectory: homeDirectory)

        for file in targets.files {
            guard fm.fileExists(atPath: file) else { continue }
            if let handle = FileHandle(forReadingAtPath: file) {
                try? handle.close()
                Logger.permissions.info("Full Disk Access check passed via file: \(file, privacy: .public)")
                return true
            }
        }

        for dir in targets.directories {
            guard fm.fileExists(atPath: dir) else { continue }
            do {
                _ = try fm.contentsOfDirectory(atPath: dir)
                Logger.permissions.info("Full Disk Access check passed via directory: \(dir, privacy: .public)")
                return true
            } catch {
                // Throws EPERM if FDA is not granted
            }
        }

        Logger.permissions.warning("Full Disk Access check: not granted")
        return false
    }
    
    /// Refreshes Full Disk Access status.
    public func refresh() {
        let liveFDA = fdaCheckClosure()
        hasFullDiskAccess = liveFDA
        if liveFDA {
            persistFDAState()
        }

        if hasFullDiskAccess && showGuidance {
            showGuidance = false
        }
    }

    /// Persists the Full Disk Access grant so the app remembers it across launches.
    private func persistFDAState() {
        fdaEverGranted = true
        userDefaults.set(true, forKey: fdaGrantedKey)
        Logger.permissions.info("Full Disk Access persisted as granted")
    }
    
    /// Opens the Full Disk Access section in System Settings.
    public func openFullDiskAccessSettings() {
        openPrivacySettings(anchor: "Privacy_AllFiles")
    }

    /// Opens Privacy & Security in System Settings, optionally targeting a specific TCC anchor.
    public func openPrivacySettings(anchor: String? = nil) {
        var urls: [String] = []
        if let anchor, !anchor.isEmpty {
            urls.append("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)")
            urls.append("x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        }
        urls.append("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        urls.append("x-apple.systempreferences:com.apple.preference.security")

        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                Logger.permissions.info("Opened Privacy settings via: \(urlString, privacy: .public)")
                return
            }
        }
    }
    
    /// Shows the guidance panel to the user if access has not yet been granted.
    /// Once permission is granted (or remembered), the prompt is one-time and not shown again.
    /// If permission has not been obtained, continues asking on launch until granted.
    public func showGuidanceIfNeeded() {
        guard !guidanceDismissed else { return }
        guard !hasFullDiskAccess else { return }
        showGuidance = true
    }
    
    /// Permanently dismisses the guidance (user preference).
    public func dismissGuidancePermanently() {
        guidanceDismissed = true
        showGuidance = false
        userDefaults.set(true, forKey: userDefaultsKey)
        Logger.permissions.info("Guidance permanently dismissed by user")
    }
    
    /// Temporarily dismisses the guidance (will show again next launch if permission not obtained).
    public func dismissGuidanceTemporarily() {
        showGuidance = false
    }

    /// Re-enables the permission guidance after a permanent dismissal and shows it,
    /// for when the user changes their mind (e.g. from Settings).
    public func requestGuidanceAgain() {
        guidanceDismissed = false
        userDefaults.set(false, forKey: userDefaultsKey)
        fdaEverGranted = false
        userDefaults.set(false, forKey: fdaGrantedKey)
        refresh()
        if !hasFullDiskAccess {
            showGuidance = true
        }
        Logger.permissions.info("Guidance re-enabled by user")
    }
}
