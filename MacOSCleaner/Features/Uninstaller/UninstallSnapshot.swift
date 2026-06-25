import Foundation

public struct UninstallSnapshot: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let appName: String
    public let bundleID: String
    public let appVersion: String?
    public let appBundlePath: String
    public let deletedPaths: [String]
    public let bypassTrash: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        appName: String,
        bundleID: String,
        appVersion: String?,
        appBundlePath: String,
        deletedPaths: [String],
        bypassTrash: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.bundleID = bundleID
        self.appVersion = appVersion
        self.appBundlePath = appBundlePath
        self.deletedPaths = deletedPaths
        self.bypassTrash = bypassTrash
    }
}
