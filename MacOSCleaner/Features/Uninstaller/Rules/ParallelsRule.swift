import Foundation

public struct ParallelsRule: ApplicationRule {
    public let displayName = "Parallels Desktop"
    public let supportedBundleIDs: Set<String> = ["com.parallels.desktop.console"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Parallels Desktop"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/parallels") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/library/parallels") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/containers/com.parallels.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/group containers/") && path.contains("com.parallels.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/applications (parallels)") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 80))
        }
        if path.contains("/.parallels_settings") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/users/shared/parallels") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/usr/local/bin/prl") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/preferences/com.parallels.desktop.console.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.parallels.desktop.console") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/application scripts/") && path.contains("com.parallels.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/saved application state/com.parallels.desktop.console") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.contains("/launchdaemons/com.parallels.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/privilegedhelpertools/com.parallels.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }

        return evidence
    }
}
