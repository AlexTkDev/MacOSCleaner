import Foundation

public struct RaycastRule: ApplicationRule {
    public let displayName = "Raycast"
    public let supportedBundleIDs: Set<String> = ["com.raycast.macos"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Raycast"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/com.raycast.macos") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/caches/com.raycast.macos") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.raycast.macos.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/saved application state/com.raycast.macos") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }

        return evidence
    }
}
