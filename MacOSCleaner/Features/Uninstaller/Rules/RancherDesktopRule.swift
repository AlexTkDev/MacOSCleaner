import Foundation

public struct RancherDesktopRule: ApplicationRule {
    public let displayName = "Rancher Desktop"
    public let supportedBundleIDs: Set<String> = ["io.rancher.desktop"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Rancher Desktop"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/rancher-desktop") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/io.rancher.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/io.rancher.desktop.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/saved application state/io.rancher.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.contains("/.local/share/rancher-desktop") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/.rd") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/privilegedhelpertools/io.rancher.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/launchdaemons/io.rancher.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }

        return evidence
    }
}
