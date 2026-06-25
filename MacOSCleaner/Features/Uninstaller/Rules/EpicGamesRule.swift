import Foundation

public struct EpicGamesRule: ApplicationRule {
    public let displayName = "Epic Games"
    public let supportedBundleIDs: Set<String> = [
        "com.epicgames.EpicGamesLauncher",
        "com.epicgames.unrealengine",
    ]
    public let supportedTeamIDs: Set<String> = [
        "95JQ5223G6",
    ]
    public let supportedAppNames: Set<String> = [
        "Epic Games Launcher", "Epic Games",
        "Unreal Engine",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/epic") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/epic games launcher") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/com.epicgames.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.epicgames.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/logs/epicgameslauncher") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/saved application state/com.epicgames.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.contains("/webcache") && path.contains("epicgames") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/vaultcache") && path.contains("epic") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/application support/epic/vaultcache") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }

        return evidence
    }
}
