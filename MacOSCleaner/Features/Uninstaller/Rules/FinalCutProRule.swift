import Foundation

public struct FinalCutProRule: ApplicationRule {
    public let displayName = "Final Cut Pro"
    public let supportedBundleIDs: Set<String> = ["com.apple.FinalCutPro"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Final Cut Pro"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/containers/com.apple.finalcutpro") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/application support/final cut pro") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.apple.finalcutpro") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.apple.finalcutpro.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/render files") || path.contains("/backup projects") {
            if path.contains("final cut pro") {
                evidence.append(ArtifactEvidence(source: .rule, weight: 60))
            }
        }

        return evidence
    }
}
