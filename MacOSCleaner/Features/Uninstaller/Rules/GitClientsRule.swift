import Foundation

public struct GitClientsRule: ApplicationRule {
    public let displayName = "Git Clients"
    public let supportedBundleIDs: Set<String> = [
        "com.github.GitHubClient",
        "com.torusknot.SourceTreeNotMAS",
        "com.DanPristupov.Fork",
        "com.fournova.Tower3",
        "com.axosoft.GitKraken",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "GitHub Desktop", "Sourcetree", "Fork", "Tower", "GitKraken",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/github desktop") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.github.githubclient") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.github.githubclient.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/logs/github desktop") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }

        if path.contains("/application support/sourcetree") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.torusknot.sourcetreenotmas") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.torusknot.sourcetreenotmas.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/logs/sourcetree") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }

        if path.contains("/application support/fork") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/com.danpristupov.fork") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/caches/com.danpristupov.fork") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.danpristupov.fork.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/application support/com.fournova.tower3") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/caches/com.fournova.tower3") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.fournova.tower3.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/application support/gitkraken") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.axosoft.gitkraken") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.axosoft.gitkraken.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        return evidence
    }
}
