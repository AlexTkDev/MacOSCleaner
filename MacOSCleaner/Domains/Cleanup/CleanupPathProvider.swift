import Foundation

public struct CleanupPath: Sendable, Equatable, Hashable {
    public let path: String
    public let category: CleanupCategory
    public let requiresSudo: Bool
    public let isDirectory: Bool
    public let description: String?

    public init(
        path: String,
        category: CleanupCategory,
        requiresSudo: Bool = false,
        isDirectory: Bool = true,
        description: String? = nil
    ) {
        self.path = path
        self.category = category
        self.requiresSudo = requiresSudo
        self.isDirectory = isDirectory
        self.description = description
    }
}

public protocol CleanupPathProvider: Sendable {
    func paths(for category: CleanupCategory) -> [CleanupPath]
    func allKnownApps() -> [String]
    func commands(for category: CleanupCategory) -> [CleanupCommand]
}

public struct CleanupCommand: Sendable, Equatable, Hashable {
    public let command: String
    public let description: String
    public let requiresSudo: Bool
    public let safe: Bool
    public let requiresRestart: Bool

    public init(
        command: String,
        description: String,
        requiresSudo: Bool = false,
        safe: Bool = true,
        requiresRestart: Bool = false
    ) {
        self.command = command
        self.description = description
        self.requiresSudo = requiresSudo
        self.safe = safe
        self.requiresRestart = requiresRestart
    }
}

public enum CleanupPathType: String, Sendable {
    case caches
    case applicationSupport = "application_support"
    case containers
    case groupContainers = "group_containers"
    case preferences
    case logs
    case savedState = "saved_state"
    case httpStorages = "http_storages"
    case webkit
    case applicationScripts = "application_scripts"
    case launchAgents = "launch_agents"
    case launchDaemons = "launch_daemons"
    case privilegedHelperTools = "privileged_helper_tools"
    case pkgReceipts = "pkg_receipts"
    case internetPlugins = "internet_plugins"
    case cookies
    case diagnosticReports = "diagnostic_reports"
    case cloudDocs = "cloud_docs"
    case sharedFileLists = "shared_file_lists"
    case developerArtifacts = "developer_artifacts"
}