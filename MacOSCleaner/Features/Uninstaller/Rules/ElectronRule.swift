import Foundation

public struct ElectronRule: ApplicationRule {
    public let displayName = "Electron"
    public let supportedBundleIDs: Set<String> = [
        "com.todesktop.230113mitalod2",     // Cursor
        "com.microsoft.VSCode",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "com.postmanlabs.mac",
        "md.obsidian",
        "com.notion.Notion",
        "com.insomnia.app",
        "com.slack.Slack",
        "com.microsoft.teams2",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "Cursor", "Visual Studio Code", "VSCode", "VSCodium",
        "Discord", "Slack", "Postman", "Obsidian", "Notion", "Insomnia",
        "Teams", "Microsoft Teams",
    ]

    private let electronArtifactDirs: Set<String> = [
        "Cache", "Code Cache", "GPUCache",
        "Local Storage", "Session Storage",
        "IndexedDB", "blob_storage", "Service Worker",
        "PartitionedStorage", "Network", "Extensions",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        let name = candidate.lastPathComponent
        var evidence: [ArtifactEvidence] = []

        let appSupportPath = "/application support/\(identity.appName.lowercased())"

        if electronArtifactDirs.contains(name) {
            if path.contains(appSupportPath) {
                evidence.append(ArtifactEvidence(source: .rule, weight: 40))
            }
        }

        if path.contains(appSupportPath) {
            evidence.append(ArtifactEvidence(source: .appName, weight: 60))
        }

        return evidence
    }

    public func matches(identity: AppIdentity) -> Bool {
        if supportedBundleIDs.contains(identity.bundleID) { return true }
        if supportedAppNames.contains(identity.appName) { return true }
        if identity.isElectron { return true }
        return false
    }
}
