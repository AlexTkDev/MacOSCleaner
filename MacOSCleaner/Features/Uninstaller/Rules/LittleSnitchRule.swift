import Foundation

public struct LittleSnitchRule: ApplicationRule {
    public let displayName = "Little Snitch"
    public let supportedBundleIDs: Set<String> = ["at.obdev.littlesnitch"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Little Snitch"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/little snitch") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/at.obdev.littlesnitch.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/launchdaemons/at.obdev.littlesnitch") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }

        return evidence
    }
}
