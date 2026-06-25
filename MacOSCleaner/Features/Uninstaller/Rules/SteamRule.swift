import Foundation

public struct SteamRule: ApplicationRule {
    public let displayName = "Steam"
    public let supportedBundleIDs: Set<String> = [
        "com.valvesoftware.steam",
    ]
    public let supportedTeamIDs: Set<String> = [
        "MXG3986M2V",
    ]
    public let supportedAppNames: Set<String> = [
        "Steam",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/steam") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/com.valvesoftware.steam") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.valvesoftware.steam") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/caches/steam") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }
        if path.contains("/application support/steam/steamapps") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/application support/steam/userdata") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/application support/steam/steamapps/compatdata") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/application support/steam/steamapps/shadercache") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }
        if path.contains("/application support/steam/steamapps/workshop") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/application support/steam/logs") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }
        if path.contains("/saved application state/com.valvesoftware.steam") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }

        return evidence
    }
}
