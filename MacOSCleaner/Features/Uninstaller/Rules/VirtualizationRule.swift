import Foundation

public struct VirtualizationRule: ApplicationRule {
    public let displayName = "Virtualization"
    public let supportedBundleIDs: Set<String> = [
        "org.virtualbox.app.VirtualBox",
        "com.utmapp.UTM",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "VirtualBox", "UTM",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/virtualbox") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/virtualbox vms") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 80))
        }
        if path.contains("/usr/local/bin/vboximg-mount") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/preferences/org.virtualbox.app.virtualbox") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/containers/com.utmapp") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/group containers/") && path.contains("com.utmapp") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 85))
        }
        if path.contains("/application scripts/") && path.contains("com.utmapp") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/opt/homebrew/bin/qemu-system-") || path.contains("/usr/local/bin/qemu-system-") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/.config/qemu") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        return evidence
    }
}
