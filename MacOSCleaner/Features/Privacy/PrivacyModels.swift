import Foundation

// MARK: - Navigation & Tabs

public enum PrivacyTab: String, CaseIterable, Identifiable, Sendable {
    case tcc
    case network
    case extensions

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .tcc: return "privacy_tab_tcc".localized
        case .network: return "privacy_tab_network".localized
        case .extensions: return "privacy_tab_extensions".localized
        }
    }

    public var iconName: String {
        switch self {
        case .tcc: return "lock.shield"
        case .network: return "network"
        case .extensions: return "puzzlepiece.extension"
        }
    }
}

// MARK: - 1.1 TCC Permissions

public enum TCCDatabaseScope: String, Sendable, Hashable {
    case user
    case system

    public var localizedTitle: String {
        switch self {
        case .user: return "privacy_tcc_scope_user".localized
        case .system: return "privacy_tcc_scope_system".localized
        }
    }
}

public enum TCCDatabaseStatus: Sendable, Equatable {
    case available(path: String)
    case requiresFullDiskAccess
    case sipProtected
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public enum TCCAuthStatus: Sendable, Hashable {
    case allowed
    case denied
    case limited
    case unknown(Int)

    public var localizedTitle: String {
        switch self {
        case .allowed: return "privacy_tcc_status_allowed".localized
        case .denied: return "privacy_tcc_status_denied".localized
        case .limited: return "privacy_tcc_status_limited".localized
        case .unknown: return "privacy_tcc_status_unknown".localized
        }
    }
}

/// Whitelisted TCC services mapped to display names, System Settings anchors, and `tccutil` keys.
public enum TCCPermissionService: Sendable, Hashable, Identifiable {
    case camera
    case microphone
    case screenCapture
    case accessibility
    case listenEvent
    case postEvent
    case fullDiskAccess
    case documentsFolder
    case desktopFolder
    case downloadsFolder
    case networkVolumes
    case removableVolumes
    case sysAdminFiles
    case contacts
    case calendar
    case reminders
    case photos
    case photosAdd
    case appleEvents
    case bluetooth
    case speechRecognition
    case mediaLibrary
    case developerTool
    case other(rawService: String)

    public var id: String { rawService }

    public init(rawService: String) {
        switch rawService {
        case "kTCCServiceCamera": self = .camera
        case "kTCCServiceMicrophone": self = .microphone
        case "kTCCServiceScreenCapture": self = .screenCapture
        case "kTCCServiceAccessibility": self = .accessibility
        case "kTCCServiceListenEvent": self = .listenEvent
        case "kTCCServicePostEvent": self = .postEvent
        case "kTCCServiceSystemPolicyAllFiles": self = .fullDiskAccess
        case "kTCCServiceSystemPolicyDocumentsFolder": self = .documentsFolder
        case "kTCCServiceSystemPolicyDesktopFolder": self = .desktopFolder
        case "kTCCServiceSystemPolicyDownloadsFolder": self = .downloadsFolder
        case "kTCCServiceSystemPolicyNetworkVolumes": self = .networkVolumes
        case "kTCCServiceSystemPolicyRemovableVolumes": self = .removableVolumes
        case "kTCCServiceSystemPolicySysAdminFiles": self = .sysAdminFiles
        case "kTCCServiceAddressBook": self = .contacts
        case "kTCCServiceCalendar": self = .calendar
        case "kTCCServiceReminders": self = .reminders
        case "kTCCServicePhotos": self = .photos
        case "kTCCServicePhotosAdd": self = .photosAdd
        case "kTCCServiceAppleEvents": self = .appleEvents
        case "kTCCServiceBluetoothAlways": self = .bluetooth
        case "kTCCServiceSpeechRecognition": self = .speechRecognition
        case "kTCCServiceMediaLibrary": self = .mediaLibrary
        case "kTCCServiceDeveloperTool": self = .developerTool
        default: self = .other(rawService: rawService)
        }
    }

    public var rawService: String {
        switch self {
        case .camera: return "kTCCServiceCamera"
        case .microphone: return "kTCCServiceMicrophone"
        case .screenCapture: return "kTCCServiceScreenCapture"
        case .accessibility: return "kTCCServiceAccessibility"
        case .listenEvent: return "kTCCServiceListenEvent"
        case .postEvent: return "kTCCServicePostEvent"
        case .fullDiskAccess: return "kTCCServiceSystemPolicyAllFiles"
        case .documentsFolder: return "kTCCServiceSystemPolicyDocumentsFolder"
        case .desktopFolder: return "kTCCServiceSystemPolicyDesktopFolder"
        case .downloadsFolder: return "kTCCServiceSystemPolicyDownloadsFolder"
        case .networkVolumes: return "kTCCServiceSystemPolicyNetworkVolumes"
        case .removableVolumes: return "kTCCServiceSystemPolicyRemovableVolumes"
        case .sysAdminFiles: return "kTCCServiceSystemPolicySysAdminFiles"
        case .contacts: return "kTCCServiceAddressBook"
        case .calendar: return "kTCCServiceCalendar"
        case .reminders: return "kTCCServiceReminders"
        case .photos: return "kTCCServicePhotos"
        case .photosAdd: return "kTCCServicePhotosAdd"
        case .appleEvents: return "kTCCServiceAppleEvents"
        case .bluetooth: return "kTCCServiceBluetoothAlways"
        case .speechRecognition: return "kTCCServiceSpeechRecognition"
        case .mediaLibrary: return "kTCCServiceMediaLibrary"
        case .developerTool: return "kTCCServiceDeveloperTool"
        case .other(let raw): return raw
        }
    }

    /// Service token accepted by `/usr/bin/tccutil reset <Service> <bundleID>`.
    /// Nil for unknown services or services that require root/MDM on modern macOS.
    public var tccutilName: String? {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .documentsFolder: return "SystemPolicyDocumentsFolder"
        case .desktopFolder: return "SystemPolicyDesktopFolder"
        case .downloadsFolder: return "SystemPolicyDownloadsFolder"
        case .networkVolumes: return "SystemPolicyNetworkVolumes"
        case .removableVolumes: return "SystemPolicyRemovableVolumes"
        case .contacts: return "AddressBook"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .photos: return "Photos"
        case .photosAdd: return "PhotosAdd"
        case .appleEvents: return "AppleEvents"
        case .bluetooth: return "BluetoothAlways"
        case .speechRecognition: return "SpeechRecognition"
        case .mediaLibrary: return "MediaLibrary"
        case .screenCapture, .accessibility, .listenEvent, .postEvent,
             .fullDiskAccess, .sysAdminFiles, .developerTool, .other:
            return nil
        }
    }

    public var systemSettingsAnchor: String {
        switch self {
        case .camera: return "Privacy_Camera"
        case .microphone: return "Privacy_Microphone"
        case .screenCapture: return "Privacy_ScreenCapture"
        case .accessibility: return "Privacy_Accessibility"
        case .listenEvent, .postEvent: return "Privacy_ListenEvent"
        case .fullDiskAccess: return "Privacy_AllFiles"
        case .documentsFolder, .desktopFolder, .downloadsFolder, .networkVolumes, .removableVolumes, .sysAdminFiles:
            return "Privacy_FilesAndFolders"
        case .contacts: return "Privacy_Contacts"
        case .calendar: return "Privacy_Calendars"
        case .reminders: return "Privacy_Reminders"
        case .photos, .photosAdd: return "Privacy_Photos"
        case .appleEvents: return "Privacy_Automation"
        case .bluetooth: return "Privacy_Bluetooth"
        case .speechRecognition: return "Privacy_SpeechRecognition"
        case .mediaLibrary: return "Privacy_Media"
        case .developerTool: return "Privacy_DevTools"
        case .other: return ""
        }
    }

    public var localizedTitle: String {
        switch self {
        case .camera: return "privacy_tcc_service_camera".localized
        case .microphone: return "privacy_tcc_service_microphone".localized
        case .screenCapture: return "privacy_tcc_service_screen".localized
        case .accessibility: return "privacy_tcc_service_accessibility".localized
        case .listenEvent: return "privacy_tcc_service_input_monitoring".localized
        case .postEvent: return "privacy_tcc_service_post_event".localized
        case .fullDiskAccess: return "privacy_tcc_service_fda".localized
        case .documentsFolder, .desktopFolder, .downloadsFolder, .networkVolumes, .removableVolumes:
            return "privacy_tcc_service_files_folders".localized
        case .sysAdminFiles: return "privacy_tcc_service_sys_admin_files".localized
        case .contacts: return "privacy_tcc_service_contacts".localized
        case .calendar: return "privacy_tcc_service_calendar".localized
        case .reminders: return "privacy_tcc_service_reminders".localized
        case .photos, .photosAdd: return "privacy_tcc_service_photos".localized
        case .appleEvents: return "privacy_tcc_service_automation".localized
        case .bluetooth: return "privacy_tcc_service_bluetooth".localized
        case .speechRecognition: return "privacy_tcc_service_speech".localized
        case .mediaLibrary: return "privacy_tcc_service_media".localized
        case .developerTool: return "privacy_tcc_service_dev_tools".localized
        case .other(let raw):
            return raw.replacingOccurrences(of: "kTCCService", with: "")
        }
    }

    public var iconName: String {
        switch self {
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .screenCapture: return "rectangle.dashed.badge.record"
        case .accessibility: return "accessibility"
        case .listenEvent, .postEvent: return "keyboard"
        case .fullDiskAccess: return "externaldrive.badge.checkmark"
        case .documentsFolder, .desktopFolder, .downloadsFolder, .networkVolumes, .removableVolumes, .sysAdminFiles:
            return "folder.badge.person.crop"
        case .contacts: return "person.crop.circle"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .photos, .photosAdd: return "photo"
        case .appleEvents: return "gearshape.2"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .speechRecognition: return "waveform"
        case .mediaLibrary: return "music.note.list"
        case .developerTool: return "hammer"
        case .other: return "lock.shield"
        }
    }
}

public struct TCCPermissionEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let service: TCCPermissionService
    public let client: String
    public let clientType: Int
    public let authStatus: TCCAuthStatus
    public let authReason: Int?
    public let lastModified: Date?
    public let scope: TCCDatabaseScope
    public let isResettable: Bool
    public let readOnlyReasonKey: String?

    public init(
        service: TCCPermissionService,
        client: String,
        clientType: Int,
        authStatus: TCCAuthStatus,
        authReason: Int? = nil,
        lastModified: Date? = nil,
        scope: TCCDatabaseScope
    ) {
        self.id = "\(scope.rawValue)|\(service.rawService)|\(client)|\(clientType)"
        self.service = service
        self.client = client
        self.clientType = clientType
        self.authStatus = authStatus
        self.authReason = authReason
        self.lastModified = lastModified
        self.scope = scope

        if scope == .system {
            self.isResettable = false
            self.readOnlyReasonKey = "privacy_tcc_readonly_system"
        } else if clientType != 0 {
            self.isResettable = false
            self.readOnlyReasonKey = "privacy_tcc_readonly_binary"
        } else if service.tccutilName == nil {
            self.isResettable = false
            self.readOnlyReasonKey = "privacy_tcc_readonly_protected"
        } else {
            self.isResettable = true
            self.readOnlyReasonKey = nil
        }
    }
}

public struct TCCAppGroup: Identifiable, Sendable, Hashable {
    public var id: String { client }
    public let client: String
    public let appName: String
    public let appURL: URL?
    public let appIdentity: AppIdentity?
    public let isRunning: Bool
    public let entries: [TCCPermissionEntry]

    public var hasResettableEntries: Bool {
        entries.contains(where: \.isResettable)
    }
}

public struct TCCSnapshot: Sendable {
    public let userDBStatus: TCCDatabaseStatus
    public let systemDBStatus: TCCDatabaseStatus
    public let groups: [TCCAppGroup]
    public let totalEntryCount: Int
}

public struct TCCSessionLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let client: String
    public let appName: String
    public let serviceTitle: String
    public let succeeded: Bool
    public let message: String
}

// MARK: - 1.2 Network Snapshot

public enum SocketProtocol: String, Sendable, Hashable {
    case tcp = "TCP"
    case udp = "UDP"
}

public struct SocketEndpoint: Sendable, Hashable {
    public let address: String
    public let port: UInt16

    public var displayString: String {
        if address.contains(":") && !address.hasPrefix("[") {
            return "[\(address)]:\(port)"
        }
        return "\(address):\(port)"
    }
}

public struct NetworkSocketItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let proto: SocketProtocol
    public let local: SocketEndpoint
    public let remote: SocketEndpoint?
    public let state: String?

    public init(
        proto: SocketProtocol,
        local: SocketEndpoint,
        remote: SocketEndpoint?,
        state: String?
    ) {
        self.id = "\(proto.rawValue)|\(local.displayString)|\(remote?.displayString ?? "*")|\(state ?? "")"
        self.proto = proto
        self.local = local
        self.remote = remote
        self.state = state
    }
}

public struct StaticNetworkProfile: Sendable, Hashable {
    public let atsAllowsArbitraryLoads: Bool
    public let atsExceptionDomains: [String]
    public let urlSchemes: [String]
    public let helperServices: [String]

    public var hasAnyCapability: Bool {
        atsAllowsArbitraryLoads
            || !atsExceptionDomains.isEmpty
            || !urlSchemes.isEmpty
            || !helperServices.isEmpty
    }
}

public struct AppNetworkItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let pid: pid_t?
    public let name: String
    public let bundleID: String?
    public let bundleURL: URL?
    public let uid: uid_t?
    public let isRunning: Bool
    public let isRestrictedByPermissions: Bool
    public let sockets: [NetworkSocketItem]
    public let staticProfile: StaticNetworkProfile?
}

public struct NetworkSnapshot: Sendable {
    public let capturedAt: Date
    public let currentUID: uid_t
    public let items: [AppNetworkItem]
    public let restrictedProcessCount: Int
    public let activeSocketCount: Int
}

// MARK: - 1.3 Browser Extensions

public enum ExtensionBrowser: String, CaseIterable, Identifiable, Sendable {
    case safari
    case chrome
    case edge
    case brave
    case arc
    case firefox

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        case .firefox: return "Firefox"
        }
    }

    public var bundleID: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .arc: return "company.thebrowser.Browser"
        case .firefox: return "org.mozilla.firefox"
        }
    }

    public var chromiumScheme: String? {
        switch self {
        case .chrome: return "chrome"
        case .edge: return "edge"
        case .brave: return "brave"
        case .arc: return "arc"
        case .safari, .firefox: return nil
        }
    }

    public var iconName: String {
        switch self {
        case .safari: return "safari"
        case .chrome, .edge, .brave, .arc, .firefox: return "globe"
        }
    }
}

public enum ExtensionSource: String, Sendable, Hashable {
    case store
    case sideload
    case system
    case unknown

    public var localizedTitle: String {
        switch self {
        case .store: return "privacy_ext_source_store".localized
        case .sideload: return "privacy_ext_source_sideload".localized
        case .system: return "privacy_ext_source_system".localized
        case .unknown: return "privacy_ext_source_unknown".localized
        }
    }
}

public enum ExtensionPermissionRisk: Int, Comparable, Sendable, Hashable {
    case normal = 0
    case elevated = 1
    case high = 2

    public static func < (lhs: ExtensionPermissionRisk, rhs: ExtensionPermissionRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var localizedTitle: String {
        switch self {
        case .normal: return "privacy_ext_risk_normal".localized
        case .elevated: return "privacy_ext_risk_elevated".localized
        case .high: return "privacy_ext_risk_high".localized
        }
    }
}

public struct BrowserExtensionItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let extensionID: String
    public let name: String
    public let version: String
    public let browser: ExtensionBrowser
    public let profileName: String?
    public let isEnabled: Bool?
    public let source: ExtensionSource
    public let permissions: [String]
    public let hostPermissions: [String]
    public let highRiskPermissions: [String]
    public let risk: ExtensionPermissionRisk
    public let bundleOrManifestURL: URL?
    public let parentAppURL: URL?
}
