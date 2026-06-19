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
    
    private let userDefaultsKey = "com.macoscleaner.guidanceDismissed"
    
    public init() {
        self.guidanceDismissed = UserDefaults.standard.bool(forKey: userDefaultsKey)
        self.hasFullDiskAccess = Self.checkFullDiskAccess()
        self.hasAccessibility = Self.checkAccessibility()
        self.hasAutomation = Self.checkAutomation()
        self.hasTrashAccess = Self.checkTrashAccess()
    }
    
    /// Checks if the application has Full Disk Access by attempting to read protected paths.
    public static func checkFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        let testPaths = [
            "/Library/Application Support",
            home + "/Library/Caches",
            home + "/Library/Application Support",
            home + "/Library/Mail",
            home + "/Library/Messages",
            home + "/Library/Safari",
            home + "/Library/Keychains",
            home + "/Library/Calendars",
            home + "/Library/Contacts",
        ]
        
        var failedPaths: [String] = []
        for path in testPaths {
            guard fm.fileExists(atPath: path) else { continue }
            do {
                _ = try fm.contentsOfDirectory(atPath: path)
            } catch {
                failedPaths.append(path)
            }
        }
        
        if !failedPaths.isEmpty {
            Logger.permissions.warning("FDA check failed for: \(failedPaths.joined(separator: ", "))")
            return false
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
        
        if hasFullDiskAccess && showGuidance {
            showGuidance = false
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
            missing.append("Full Disk Access")
        }
        if !hasAccessibility {
            missing.append("Accessibility")
        }
        if !hasAutomation {
            missing.append("Automation (Apple Events)")
        }
        if !hasTrashAccess {
            missing.append("Trash Access")
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
}
