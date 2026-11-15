import Foundation

public struct NordVPNRule: ApplicationRule {
    public let displayName = "NordVPN"
    public let supportedBundleIDs: Set<String> = ["com.nordvpn.macos"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["NordVPN"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        let bundle = identity.bundleID.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/nordvpn") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/launchdaemons/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/privilegedhelpertools/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }

        let team = identity.teamID?.lowercased()
        let ownsPath = path.contains(bundle) || path.contains("com.nordvpn.") || (team.map { path.contains($0) } ?? false)
        if ownsPath && (path.contains("/systemextensions/") || path.contains("/stagedextensions/")) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }

        return evidence
    }
}
