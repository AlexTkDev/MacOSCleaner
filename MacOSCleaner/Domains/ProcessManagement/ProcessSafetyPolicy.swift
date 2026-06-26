import Foundation

public enum KillPermission: Sendable {
    case allowed
    case blocked(reason: String)
    case needsConfirmation(reason: String)
}

public struct ProcessSafetyPolicy: Sendable {
    private let protectedProcesses: Set<String>
    private var userBlacklist: Set<String>
    private var userWhitelist: Set<String>

    public init(
        protectedProcesses: Set<String> = Self.defaultProtected,
        userBlacklist: Set<String> = [],
        userWhitelist: Set<String> = []
    ) {
        self.protectedProcesses = protectedProcesses
        self.userBlacklist = userBlacklist
        self.userWhitelist = userWhitelist
    }

    public static let defaultProtected: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
        "loginwindow",
        "symptomsd",
        "WiFiAgent",
        "bluetoothd",
        "cfprefsd",
        "coreaudiod",
        "diskarbitrationd",
        "fseventsd",
        "opendirectoryd",
        "securityd",
        "systemstats",
        "trustd",
        "usernoted",
        "launchservicesd",
        "ScreensharingAgent",
        "ControlCenter",
        "Dock",
        "Finder",
        "SystemUIServer",
        "Activity Monitor",
    ]

    public func isKillable(_ process: RunningProcess) -> KillPermission {
        let name = process.name

        if process.pid <= 1 {
            return .blocked(reason: String(format: "process_block_pid_format".localized, process.pid))
        }

        if userWhitelist.contains(name) {
            return .blocked(reason: String(format: "process_block_whitelist_name_format".localized, name))
        }

        if let bundleID = process.bundleID, userWhitelist.contains(bundleID) {
            return .blocked(reason: String(format: "process_block_whitelist_bundle_format".localized, bundleID))
        }

        if protectedProcesses.contains(name) {
            return .blocked(reason: String(format: "process_block_protected_format".localized, name))
        }

        if userBlacklist.contains(name) {
            return .allowed
        }

        if let bundleID = process.bundleID, userBlacklist.contains(bundleID) {
            return .allowed
        }

        if process.path == nil {
            return .needsConfirmation(reason: String(format: "process_block_no_path_format".localized, name))
        }

        return .allowed
    }

    public mutating func addToBlacklist(_ name: String) {
        userBlacklist.insert(name)
        userWhitelist.remove(name)
    }

    public mutating func removeFromBlacklist(_ name: String) {
        userBlacklist.remove(name)
    }

    public mutating func addToWhitelist(_ name: String) {
        userWhitelist.insert(name)
        userBlacklist.remove(name)
    }

    public mutating func removeFromWhitelist(_ name: String) {
        userWhitelist.remove(name)
    }

    public var blacklist: Set<String> { userBlacklist }
    public var whitelist: Set<String> { userWhitelist }
    public var protected: Set<String> { protectedProcesses }
}
