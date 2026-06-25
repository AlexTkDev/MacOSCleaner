import Foundation

public struct VMwareFusionRule: ApplicationRule {
    public let displayName = "VMware Fusion"
    public let supportedBundleIDs: Set<String> = ["com.vmware.fusion"]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = ["VMware Fusion"]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/vmware fusion") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/vmware") && !path.contains("fusion") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.vmware.fusion") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.vmware.fusion.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/preferences/com.vmware.fusionstartmenu.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/virtual machines") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 80))
        }
        if path.contains("/preferences/vmware fusion") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/extensions/vmmon.kext") || path.contains("/extensions/vmnet.kext") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if path.contains("/launchdaemons/com.vmware") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/privilegedhelpertools/com.vmware") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }

        return evidence
    }
}
