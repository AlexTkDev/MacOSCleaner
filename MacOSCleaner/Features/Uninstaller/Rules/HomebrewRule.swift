import Foundation

public struct HomebrewRule: ApplicationRule {
    public let displayName = "Homebrew"
    public let supportedBundleIDs: Set<String> = []
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "Homebrew", "brew",
    ]

    public init() {}

    public func matches(identity: AppIdentity) -> Bool {
        if supportedAppNames.contains(identity.appName) { return true }
        if identity.bundleID == "N/A (CLI tool)" { return true }
        return false
    }

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.hasPrefix("/usr/local/homebrew") || path.hasPrefix("/opt/homebrew") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if path.contains("/caches/homebrew") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/logs/homebrew") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }
        if path.contains("/caskroom") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/cellar") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.hasPrefix("/usr/local/bin/brew") || path.hasPrefix("/opt/homebrew/bin/brew") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }

        return evidence
    }
}
