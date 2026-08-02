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

        let parent = candidate.deletingLastPathComponent().lastPathComponent
        if identity.vendorNames.contains(name) || identity.vendorNames.contains(parent) {
            let mega = Set(["Google", "Microsoft", "Adobe", "Oracle", "Apple"])
            // Bare mega-vendor roots are shared across suite apps — do not boost.
            let parentPath = candidate.deletingLastPathComponent().path
            let isBareMegaRoot = mega.contains(name) && (
                parent == "Application Support" || parent == "Caches" || parent == "Logs"
                    || parent == "Library" || parentPath.hasSuffix("/Library")
            )
            if !isBareMegaRoot {
                evidence.append(ArtifactEvidence(source: .rule, weight: 30))
            }
        }
        if parent == "Containers" && name == identity.bundleID {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if parent == "Group Containers" && (name == "group.\(identity.bundleID)" || name.hasPrefix("group.\(identity.bundleID).")) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if parent == "Group Containers", identity.appGroups.contains(name) {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        } else if parent == "Group Containers", let teamID = identity.teamID, name.hasPrefix(teamID + ".") {
            let suffix = String(name.dropFirst(teamID.count + 1)).lowercased()
            if suffix == identity.bundleID.lowercased() || EvidenceProbe.bundleIDSuffixMatch(suffix, bundleID: identity.bundleID.lowercased()) {
                evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
            }
        }

        if path.contains("/library/caches/") || path.contains("/library/logs/") {
            if name.lowercased() == identity.bundleID.lowercased() || name.lowercased().hasPrefix(identity.bundleID.lowercased() + ".") {
                evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
            }
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
