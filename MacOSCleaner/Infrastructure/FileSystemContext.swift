import Foundation

/// Isolates filesystem roots for production vs tests.
/// Destructive operations must stay inside `allowedRoots` when `enforceAllowedRoots` is true.
public struct FileSystemContext: Sendable {
    public let homeDirectory: URL
    public let allowedRoots: [URL]
    /// When true, any mutation/scan outside `allowedRoots` fails closed before filesystem changes.
    public let enforceAllowedRoots: Bool

    public init(
        homeDirectory: URL,
        allowedRoots: [URL]? = nil,
        enforceAllowedRoots: Bool = true
    ) {
        let home = homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        self.homeDirectory = home
        self.enforceAllowedRoots = enforceAllowedRoots
        if let allowedRoots {
            self.allowedRoots = allowedRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        } else {
            let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            self.allowedRoots = [
                home,
                URL(fileURLWithPath: "/Library", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                URL(fileURLWithPath: "/private/tmp", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                URL(fileURLWithPath: "/tmp", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                URL(fileURLWithPath: "/usr/local", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                URL(fileURLWithPath: "/opt/homebrew", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                temp,
            ]
        }
    }

    public static var production: FileSystemContext {
        FileSystemContext(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            enforceAllowedRoots: true
        )
    }

    /// UUID temp root for tests — all destructive work must stay under this root.
    public static func isolatedTestRoot(fileManager: FileManager = .default) throws -> FileSystemContext {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MacOSCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let home = root.appendingPathComponent("Home", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        return FileSystemContext(
            homeDirectory: home,
            allowedRoots: [root],
            enforceAllowedRoots: true
        )
    }

    public var homePath: String { homeDirectory.path }

    public func isInsideAllowedRoots(_ url: URL) -> Bool {
        let stdPath = url.standardizedFileURL.path
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return allowedRoots.contains { root in
            let rootStd = root.standardizedFileURL.path
            let rootResolved = root.resolvingSymlinksInPath().standardizedFileURL.path
            return stdPath == rootStd || stdPath.hasPrefix(rootStd + "/") ||
                   resolvedPath == rootResolved || resolvedPath.hasPrefix(rootResolved + "/") ||
                   stdPath == rootResolved || stdPath.hasPrefix(rootResolved + "/") ||
                   resolvedPath == rootStd || resolvedPath.hasPrefix(rootStd + "/")
        }
    }

    /// Fail-closed guard for destructive test operations.
    public func assertAllowedForMutation(_ url: URL) throws {
        guard enforceAllowedRoots else { return }
        guard isInsideAllowedRoots(url) else {
            throw SafetyError.protectedPath("outside test root: \(url.path)")
        }
    }
}
