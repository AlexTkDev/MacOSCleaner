import Foundation

public struct DefaultRule: ApplicationRule {
    public let displayName = "Generic"
    public let supportedBundleIDs: Set<String> = []
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = []

    public init() {}

    public func matches(identity: AppIdentity) -> Bool { true }

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        let name = candidate.lastPathComponent
        var evidence: [ArtifactEvidence] = []

        if name == identity.bundleID || name.hasPrefix(identity.bundleID + ".") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 100))
        }

        if name == identity.appName || name.hasPrefix(identity.appName + " ") || name.hasPrefix(identity.appName + "-") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 60))
        }

        if identity.vendorNames.contains(name) || identity.vendorNames.contains(candidate.deletingLastPathComponent().lastPathComponent) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 30))
        }

        let parent = candidate.deletingLastPathComponent().lastPathComponent
        if parent == "Containers" && name == identity.bundleID {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if parent == "Group Containers" && (name == "group.\(identity.bundleID)" || name.hasPrefix("group.\(identity.bundleID).")) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }

        if path.contains("/launchagents/") || path.contains("/launchdaemons/") {
            if path.contains(identity.bundleID.lowercased()) || name.lowercased().contains(identity.appName.lowercased()) {
                evidence.append(ArtifactEvidence(source: .rule, weight: 70))
            }
        }

        if name == identity.executableName {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }

        return evidence
    }
}
