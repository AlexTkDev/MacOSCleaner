import Foundation

public struct BrowserRule: ApplicationRule {
    public let displayName = "Browser"
    public let supportedBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.chromium.Chromium",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.canary",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser",
    ]
    public let supportedTeamIDs: Set<String> = [
        "EQHXZ8M8AV",  // Google
        "UBF8T346G9",  // Mozilla
        "BFYZ25A2P4",  // Brave
    ]
    public let supportedAppNames: Set<String> = [
        "Google Chrome", "Chrome", "Chromium", "Brave Browser", "Brave",
        "Microsoft Edge", "Edge", "Firefox", "Firefox Developer Edition",
        "Arc",
    ]

    private let browserArtifactDirs: Set<String> = [
        "Default", "Profile", "Profiles",
        "IndexedDB", "GPUCache", "Code Cache",
        "Service Worker", "CacheStorage",
        "Session Storage", "Local Extension Storage",
        "blob_storage", "File System",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        let name = candidate.lastPathComponent
        var evidence: [ArtifactEvidence] = []

        if browserArtifactDirs.contains(name) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }

        if path.contains("/application support/\(identity.appName.lowercased())") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 60))
        }

        if path.contains("/caches/\(identity.appName.lowercased())") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }

        return evidence
    }
}
