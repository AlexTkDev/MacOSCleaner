import Darwin
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

public enum CleanupPathExpander {
    /// Hard cap on glob fan-out to keep scans bounded.
    public static let defaultMaxMatches = 256

    /// Expands `~` and simple `*`/`?` path components; returns only existing paths.
    /// Skips symlink directories; stops after `maxMatches`.
    public static func expand(
        _ template: String,
        home: String,
        fileManager: FileManager = .default,
        maxMatches: Int = CleanupPathExpander.defaultMaxMatches
    ) -> [String] {
        let absolute = template.hasPrefix("~") ? home + template.dropFirst() : template
        guard absolute.contains("*") || absolute.contains("?") else {
            return fileManager.fileExists(atPath: absolute) ? [absolute] : []
        }
        var matches = [""]
        for component in absolute.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            var next: [String] = []
            if component.contains("*") || component.contains("?") {
                for base in matches {
                    let dir = base.isEmpty ? "/" : base
                    let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
                    if Self.isSymlinkDirectory(dirURL, fileManager: fileManager) { continue }
                    guard let children = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
                    for child in children where Self.fnmatch(pattern: component, string: child) {
                        let childPath = base + "/" + child
                        if Self.isSymlinkDirectory(URL(fileURLWithPath: childPath), fileManager: fileManager) {
                            continue
                        }
                        next.append(childPath)
                        if next.count >= maxMatches { return Array(next.prefix(maxMatches)) }
                    }
                }
            } else {
                for base in matches {
                    let candidate = base + "/" + component
                    if fileManager.fileExists(atPath: candidate) { next.append(candidate) }
                    if next.count >= maxMatches { return Array(next.prefix(maxMatches)) }
                }
            }
            matches = next
            if matches.isEmpty { return [] }
            if matches.count > maxMatches {
                return Array(matches.prefix(maxMatches))
            }
        }
        return matches
    }

    private static func isSymlinkDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attrs[.type] as? FileAttributeType else { return false }
        return type == .typeSymbolicLink
    }

    private static func fnmatch(pattern: String, string: String) -> Bool {
        #if canImport(Darwin)
        return Darwin.fnmatch(pattern, string, 0) == 0
        #else
        return string == pattern
        #endif
    }
}