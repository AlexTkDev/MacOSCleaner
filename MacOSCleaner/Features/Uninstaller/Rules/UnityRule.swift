import Foundation

public struct UnityRule: ApplicationRule {
    public let displayName = "Unity"
    public let supportedBundleIDs: Set<String> = [
        "com.unity3d.unityhub",
        "com.unity3d.UnityEditor5.x",
        "com.unity3d.UnityEditor",
    ]
    public let supportedTeamIDs: Set<String> = [
        "7S365J7V36",
    ]
    public let supportedAppNames: Set<String> = [
        "Unity Hub", "Unity",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/unity") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/unity hub") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/com.unity3d.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.unity3d.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/caches/unity") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }
        if path.contains("/logs/unity") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/logs/unity hub") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/saved application state/com.unity3d.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.hasSuffix("/.local/share/unity3d") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/library/unity/packagecache") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        return evidence
    }
}
