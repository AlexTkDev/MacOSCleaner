import Foundation

public struct XcodeRule: ApplicationRule {
    public let displayName = "Xcode"
    public let supportedBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.apple.dt.xcode",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["Xcode"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/containers/com.apple.dt.xcode") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 100))
        }
        if path.contains("/application scripts/com.apple.dt.xcode") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/developer/xcode/userdata") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/developer/xcode/devicesupport") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/mobiledevice/provisioning profiles") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/preferences/com.apple.dt.xcode.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/saved application state/com.apple.dt.xcode.savedstate") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }

        return evidence
    }
}
