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

    public init() {
        self.guidanceDismissed = UserDefaults.standard.bool(forKey: userDefaultsKey)
        self.fdaEverGranted = UserDefaults.standard.bool(forKey: fdaGrantedKey)
        self.hasFullDiskAccess = Self.checkFullDiskAccess()
        self.hasAccessibility = Self.checkAccessibility()
        self.hasAutomation = Self.checkAutomation()
        self.hasTrashAccess = Self.checkTrashAccess()
        persistFDAState()
    }
    
    /// Checks if the application has Full Disk Access by attempting to read protected paths.
    public static func checkFullDiskAccess() -> Bool {
        let fm = FileManager.default
        
        // Directories with restricted permissions — listing contents requires FDA
        let protectedPaths = [
            "/Library/Application Support/com.apple.TCC",
            "/private/var/db/dslocal",
        ]
        
        var checked = false
        for path in protectedPaths {
            guard fm.fileExists(atPath: path) else { continue }
            checked = true
            do {
                _ = try fm.contentsOfDirectory(atPath: path)
            } catch {
                Logger.permissions.warning("FDA check failed at: \(path)")
                return false
            }
        }
        
        // Fallback for older macOS — try Keychains with attribute check
        if !checked {
            let keychains = "/Library/Keychains"
            if fm.fileExists(atPath: keychains) {
                do {
                    // attributesOfItem requires read access to the item metadata,
                    // which is a stronger check than listing parent directory
                    _ = try fm.attributesOfItem(atPath: keychains)
                    if let items = try? fm.contentsOfDirectory(atPath: keychains),
                       let first = items.first {
                        _ = try fm.attributesOfItem(atPath: keychains + "/" + first)
                    }
                } catch {
                    Logger.permissions.warning("FDA check failed at: \(keychains)")
                    return false
                }
            }
        }
        
        Logger.permissions.info("Full Disk Access check passed")
        return true
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
        hasFullDiskAccess = Self.checkFullDiskAccess()
        hasAccessibility = Self.checkAccessibility()
        hasAutomation = Self.checkAutomation()
        hasTrashAccess = Self.checkTrashAccess()
        persistFDAState()

        if hasFullDiskAccess && showGuidance {
            showGuidance = false
        }
    }

    /// Persists the Full Disk Access grant so the app remembers it across launches.
    private func persistFDAState() {
        if hasFullDiskAccess {
            fdaEverGranted = true
            UserDefaults.standard.set(true, forKey: fdaGrantedKey)
        }
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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
        Logger.permissions.info("Opened Full Disk Access settings")
    }
    
    /// Opens Accessibility settings in System Settings.
    public func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        Logger.permissions.info("Opened Accessibility settings")
    }
    
    /// Opens Automation settings in System Settings.
    public func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
        Logger.permissions.info("Opened Automation settings")
    }
    
    /// Opens System Settings Privacy & Security main page.
    public func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }
    
    /// Shows the guidance panel to the user.
    public func showGuidanceIfNeeded() {
        guard !guidanceDismissed else { return }
        guard !hasFullDiskAccess else { return }
        showGuidance = true
    }
    
    /// Permanently dismisses the guidance (user preference).
    public func dismissGuidancePermanently() {
        guidanceDismissed = true
        showGuidance = false
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
        Logger.permissions.info("Guidance permanently dismissed by user")
    }
    
    /// Temporarily dismisses the guidance (will show again next launch).
    public func dismissGuidanceTemporarily() {
        showGuidance = false
    }

    /// Re-enables the permission guidance after a permanent dismissal and shows it,
    /// for when the user changes their mind (e.g. from Settings).
    public func requestGuidanceAgain() {
        guidanceDismissed = false
        UserDefaults.standard.set(false, forKey: userDefaultsKey)
        refresh()
        if !hasFullDiskAccess {
            showGuidance = true
        }
        Logger.permissions.info("Guidance re-enabled by user")
    }
}
