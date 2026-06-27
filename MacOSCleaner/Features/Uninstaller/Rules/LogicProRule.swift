import Foundation

public struct LogicProRule: ApplicationRule {
    public let displayName = "Logic Pro"
    public let supportedBundleIDs: Set<String> = ["com.apple.Logic10"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Logic Pro", "Logic Pro X"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/containers/com.apple.logic10") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/application support/logic") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.apple.logic10") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.apple.logic10.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/audio/plug-ins/components") ||
           path.contains("/audio/plug-ins/vst") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }

        return evidence
    }
}
