import Foundation
import AppKit
import os.log
import ApplicationServices

private extension Logger {
    static let permissions = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macoscleaner", category: "PermissionsManager")
}

/// Manages file system permissions and guides users through granting access.
@Observable
public final class PermissionsManager {
    /// Whether the app has Full Disk Access.
    public private(set) var hasFullDiskAccess = false
    
    /// Whether the app has Accessibility access.
    public private(set) var hasAccessibility = false
    
    /// Whether the app has Automation (Apple Events) access.
    public private(set) var hasAutomation = false
    
    /// Whether Trash access was granted.
    public private(set) var hasTrashAccess = false
    
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
        self.hasFullDiskAccess = liveFDA || self.fdaEverGranted
        self.hasAccessibility = Self.checkAccessibility()
        self.hasAutomation = Self.checkAutomation()
        self.hasTrashAccess = Self.checkTrashAccess()
        if liveFDA {
            persistFDAState()
        }
    }
    
    /// Checks if the application has Full Disk Access by attempting to read protected paths.
    public static func checkFullDiskAccess() -> Bool {
        let fm = FileManager.default

        // 1. Check system TCC.db (POSIX 644 world-readable, guarded by macOS TCC)
        let systemTCC = "/Library/Application Support/com.apple.TCC/TCC.db"
        if fm.fileExists(atPath: systemTCC) {
            if let handle = FileHandle(forReadingAtPath: systemTCC) {
                try? handle.close()
                Logger.permissions.info("Full Disk Access check passed via system TCC.db")
                return true
            }
        }

        // 2. Check user-level TCC protected directories (listing requires FDA)
        let homeDir = fm.homeDirectoryForCurrentUser.path
        let userTCCDirs = [
            homeDir + "/Library/Suggestions",
            homeDir + "/Library/Mail"
        ]
        for dir in userTCCDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            do {
                _ = try fm.contentsOfDirectory(atPath: dir)
                Logger.permissions.info("Full Disk Access check passed via directory: \(dir)")
                return true
            } catch {
                // Throws EPERM if FDA is not granted
            }
        }

        // 3. Check Safari protected files
        let safariFiles = [
            homeDir + "/Library/Safari/CloudTabs.db",
            homeDir + "/Library/Safari/Bookmarks.plist"
        ]
        for file in safariFiles {
            guard fm.fileExists(atPath: file) else { continue }
            if let handle = FileHandle(forReadingAtPath: file) {
                try? handle.close()
                Logger.permissions.info("Full Disk Access check passed via Safari file: \(file)")
                return true
            }
        }

        Logger.permissions.warning("Full Disk Access check: not granted")
        return false
    }
    
    /// Checks if the app has Accessibility (AX) access.
    nonisolated public static func checkAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }
    
    /// Checks if the app can send Apple Events (Automation).
    public static func checkAutomation() -> Bool {
        let script = NSAppleScript(source: "return \"ok\"")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        let success = error == nil && result?.stringValue == "ok"
        Logger.permissions.info("Automation access: \(success ? "granted" : "denied")")
        return success
    }
    
    /// Checks if the app can access Trash.
    public static func checkTrashAccess() -> Bool {
        let fm = FileManager.default
        let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        return (try? fm.contentsOfDirectory(atPath: trashURL.path)) != nil
    }
    
    /// Refreshes all permission statuses.
    public func refresh() {
        let liveFDA = fdaCheckClosure()
        hasFullDiskAccess = liveFDA || fdaEverGranted
        hasAccessibility = Self.checkAccessibility()
        hasAutomation = Self.checkAutomation()
        hasTrashAccess = Self.checkTrashAccess()
        if liveFDA {
            persistFDAState()
        }

        if (hasFullDiskAccess || fdaEverGranted) && showGuidance {
            showGuidance = false
        }
    }

    /// Persists the Full Disk Access grant so the app remembers it across launches.
    private func persistFDAState() {
        fdaEverGranted = true
        userDefaults.set(true, forKey: fdaGrantedKey)
        Logger.permissions.info("Full Disk Access persisted as granted")
    }
    
    /// Returns true if all critical permissions are granted.
    public var allCriticalPermissionsGranted: Bool {
        hasFullDiskAccess
    }
    
    /// Returns a list of missing permission descriptions.
    public var missingPermissions: [String] {
        var missing: [String] = []
        if !hasFullDiskAccess {
            missing.append("permissions.full_disk_access".localized)
        }
        if !hasAccessibility {
            missing.append("permissions.accessibility".localized)
        }
        if !hasAutomation {
            missing.append("permissions.automation".localized)
        }
        if !hasTrashAccess {
            missing.append("permissions.trash_access".localized)
        }
        return missing
    }
    
    /// Opens the Full Disk Access section in System Settings.
    public func openFullDiskAccessSettings() {
        // macOS 13+ (Ventura/Sonoma/Sequoia) URL scheme for Full Disk Access
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                Logger.permissions.info("Opened Full Disk Access settings via: \(urlString, privacy: .public)")
                return
            }
        }
    }
    
    /// Opens Accessibility settings in System Settings.
    public func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                Logger.permissions.info("Opened Accessibility settings via: \(urlString, privacy: .public)")
                return
            }
        }
    }
    
    /// Opens Automation settings in System Settings.
    public func openAutomationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                Logger.permissions.info("Opened Automation settings via: \(urlString, privacy: .public)")
                return
            }
        }
    }
    
    /// Opens System Settings Privacy & Security main page.
    public func openPrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
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
        guard !hasFullDiskAccess && !fdaEverGranted else { return }
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
