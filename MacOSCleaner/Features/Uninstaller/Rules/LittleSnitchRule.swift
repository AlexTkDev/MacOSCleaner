import Foundation

public struct LittleSnitchRule: ApplicationRule {
    public let displayName = "Little Snitch"
    public let supportedBundleIDs: Set<String> = [
        "at.obdev.littlesnitch",
        "at.obdev.LittleSnitchNetworkExtension",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Little Snitch"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        let bundle = identity.bundleID.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/little snitch") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/extensions/littlesnitch"),
           !path.contains("/systemextensions/"),
           !path.contains("/stagedextensions/") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/preferences/at.obdev.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/launchdaemons/at.obdev.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/privilegedhelpertools/at.obdev.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }

        let team = identity.teamID?.lowercased()
        let ownsPath = path.contains(bundle) || path.contains("at.obdev.") || (team.map { path.contains($0) } ?? false)
        if ownsPath && (path.contains("/systemextensions/") || path.contains("/stagedextensions/")) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }

        return evidence
    }
}
