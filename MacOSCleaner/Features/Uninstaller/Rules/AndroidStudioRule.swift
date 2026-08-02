import Foundation

public struct AndroidStudioRule: ApplicationRule {
    public let displayName = "Android Studio"
    public let supportedBundleIDs: Set<String> = [
        "com.google.android.studio",
    ]
    public let supportedTeamIDs: Set<String> = [
        "EQHXZ8M8AV",
    ]
    public let supportedAppNames: Set<String> = ["Android Studio"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/google/androidstudio") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/google/androidstudio") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }
        if path.contains("/logs/google/androidstudio") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/preferences/com.google.android.studio.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        // Whole Android SDK tree + home tooling — uninstall should treat as guaranteed.
        if path.contains("/library/android") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 100))
        } else if path.contains("/android/sdk") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 100))
        }
        if path.contains("/.gradle") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 100))
        }
        if path.contains("/.android") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 100))
        }

        return evidence
    }
}
