import Foundation

public struct AlfredRule: ApplicationRule {
    public let displayName = "Alfred"
    public let supportedBundleIDs: Set<String> = ["com.runningwithcrayons.Alfred-Preferences"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Alfred", "Alfred 5"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/alfred") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.runningwithcrayons.alfred") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.runningwithcrayons.alfred-preferences.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        return evidence
    }
}
