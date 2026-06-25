import Foundation

public struct NetworkExtensionRule: ApplicationRule {
    public let displayName = "Network Extension"
    public let supportedBundleIDs: Set<String> = [
        "at.obdev.littlesnitch",
        "at.obdev.LittleSnitchNetworkExtension",
        "com.nordvpn.macos",
        "com.expressvpn.ExpressVPN",
        "com.tunnelbear.mac",
        "com.protonvpn.mac",
        "com.windscribe.macos",
        "com.surfshark.vpnclient",
        "com.privateinternetaccess.PIA",
        "com.ipvanish",
        "com.vyprvpn.mac",
    ]
    public let supportedTeamIDs: Set<String> = [
        "TDNWQ5M53F",  // ProtonVPN
    ]
    public let supportedAppNames: Set<String> = [
        "Little Snitch",
        "NordVPN",
        "ExpressVPN",
        "TunnelBear",
        "ProtonVPN",
        "Windscribe",
        "Surfshark",
        "Private Internet Access", "PIA",
        "IPVanish",
        "VyprVPN",
    ]

    public init() {}

    public func matches(identity: AppIdentity) -> Bool {
        if supportedBundleIDs.contains(identity.bundleID) { return true }
        if let tid = identity.teamID, supportedTeamIDs.contains(tid) { return true }
        if supportedAppNames.contains(identity.appName) { return true }
        let lower = identity.appName.lowercased()
        return lower.contains("vpn") || lower.contains("snitch") || lower.contains("firewall")
    }

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/little snitch") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/extensions/littlesnitch") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/stagedextensions/") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if path.contains("/launchdaemons/at.obdev.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/privilegedhelpertools/at.obdev.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/preferences/at.obdev.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/application support/nordvpn") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/launchdaemons/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/privilegedhelpertools/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/caches/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.nordvpn.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/systemextensions/") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }

        return evidence
    }
}
