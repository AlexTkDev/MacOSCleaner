import Foundation

public struct DaVinciResolveRule: ApplicationRule {
    public let displayName = "DaVinci Resolve"
    public let supportedBundleIDs: Set<String> = ["com.blackmagic-design.DaVinciResolve"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["DaVinci Resolve"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/blackmagic design/davinci resolve") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/blackmagic design") && !path.contains("davinci") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.blackmagic-design.davinciresolve") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.blackmagic-design.davinciresolve.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/logs/davinciresolve") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/cacheclip") || path.contains("/resolve disk database") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }

        return evidence
    }
}
