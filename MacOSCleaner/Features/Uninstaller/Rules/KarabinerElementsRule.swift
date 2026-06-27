import Foundation

public struct KarabinerElementsRule: ApplicationRule {
    public let displayName = "Karabiner Elements"
    public let supportedBundleIDs: Set<String> = ["org.pqrs.Karabiner-Elements.Preferences"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Karabiner-Elements", "Karabiner Elements"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/org.pqrs/karabiner-elements") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/preferences/org.pqrs.karabiner-elements.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/launchdaemons/org.pqrs.karabiner") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/extensions/org.pqrs.karabiner") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }

        return evidence
    }
}
