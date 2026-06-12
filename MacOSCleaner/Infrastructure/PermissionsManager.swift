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
    
    private let userDefaultsKey = "com.macoscleaner.guidanceDismissed"
    
    public init() {
        self.guidanceDismissed = UserDefaults.standard.bool(forKey: userDefaultsKey)
        self.hasFullDiskAccess = Self.checkFullDiskAccess()
    }
    
    /// Checks if the application has Full Disk Access by attempting to read a protected path.
    public static func checkFullDiskAccess() -> Bool {
        let fm = FileManager.default
        
        // Try to access a path that requires FDA
        let testPaths = [
            "/Library/Application Support",
            NSHomeDirectory() + "/Library/Caches",
            NSHomeDirectory() + "/Library/Application Support"
        ]
        
        for path in testPaths {
            guard fm.fileExists(atPath: path) else { continue }
            guard let _ = try? fm.contentsOfDirectory(atPath: path) else {
                Logger.permissions.warning("FDA check failed for: \(path)")
                return false
            }
        }
        
        Logger.permissions.info("Full Disk Access check passed")
        return true
    }
    
    /// Refreshes the FDA status.
    public func refresh() {
        hasFullDiskAccess = Self.checkFullDiskAccess()
        
        if hasFullDiskAccess && showGuidance {
            showGuidance = false
        }
    }
    
    /// Opens the Full Disk Access section in System Settings.
    public func openFullDiskAccessSettings() {
        // macOS Ventura+ (13.0+)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
        Logger.permissions.info("Opened Full Disk Access settings")
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
