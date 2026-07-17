import Foundation

public struct DockerRule: ApplicationRule {
    public let displayName = "Docker"
    public let supportedBundleIDs: Set<String> = [
        "com.docker.docker",
        "com.docker.orbstack",
        "dev.orbstack",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Docker", "OrbStack"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.hasSuffix("/containers/com.docker.docker") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 100))
        }
        if path.contains("/group containers/group.com.docker") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/application support/docker") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 60))
        }
        if path.contains("/containers/com.docker.orbstack") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 100))
        }
        if path.contains("/group containers/") && path.contains("orbstack") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/caches/com.docker") || path.contains("/caches/dev.orbstack") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/logs/") && path.contains("orbstack") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        // User VM data outside ~/Library (~/Documents/.../Orbstack_files, …)
        if path.contains("orbstack") && (path.contains("/documents/") || path.contains("/desktop/") || path.contains("/users/shared/")) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 85))
        }

        if path.hasSuffix(".raw") || path.hasSuffix(".qcow2") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }

        return evidence
    }
}
