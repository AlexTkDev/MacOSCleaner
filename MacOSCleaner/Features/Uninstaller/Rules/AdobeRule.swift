import Foundation

public struct AdobeRule: ApplicationRule {
    public let displayName = "Adobe"
    public let supportedBundleIDs: Set<String> = [
        "com.adobe.ccx.process",
        "com.adobe.Photoshop",
        "com.adobe.Illustrator",
        "com.adobe.PremierePro",
        "com.adobe.AfterEffects",
        "com.adobe.InDesign",
        "com.adobe.LightroomClassic",
        "com.adobe.Lightroom",
        "com.adobe.Acrobat.Pro",
        "com.adobe.Acrobat.Reader",
        "com.adobe.AfterEffects",
        "com.audition",
        "com.adobe.Animate",
        "com.adobe.Dreamweaver",
        "com.adobe.BrIDGE",
        "com.adobe.indesign",
        "com.adobe Prelude",
        "com.adobe.MediaEncoder",
        "com.adobe.spank",
    ]
    public let supportedTeamIDs: Set<String> = [
        "JQ5W7278T3",
    ]
    public let supportedAppNames: Set<String> = [
        "Adobe Creative Cloud", "Creative Cloud",
        "Photoshop", "Adobe Photoshop",
        "Illustrator", "Adobe Illustrator",
        "Premiere Pro", "Adobe Premiere Pro",
        "After Effects", "Adobe After Effects",
        "InDesign", "Adobe InDesign",
        "Lightroom Classic", "Adobe Lightroom Classic",
        "Lightroom", "Adobe Lightroom",
        "Acrobat", "Adobe Acrobat",
        "Audition", "Adobe Audition",
        "Animate", "Adobe Animate",
        "Dreamweaver", "Adobe Dreamweaver",
        "Bridge", "Adobe Bridge",
        "Prelude", "Adobe Prelude",
        "Media Encoder", "Adobe Media Encoder",
    ]

    public init() {}

    public func matches(identity: AppIdentity) -> Bool {
        if supportedBundleIDs.contains(identity.bundleID) { return true }
        if let tid = identity.teamID, supportedTeamIDs.contains(tid) { return true }
        if supportedAppNames.contains(identity.appName) { return true }
        let lower = identity.appName.lowercased()
        return lower.hasPrefix("adobe") || lower.contains("creative cloud")
    }

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/adobe") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/com.adobe.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.adobe.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/caches/adobe") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }
        if path.contains("/logs/adobe") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/launchagents/com.adobe.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/launchdaemons/com.adobe.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/saved application state/com.adobe.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.hasSuffix("/.adobe") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.hasSuffix("/creative cloud files") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/application support/adobe/") {
            let components = path.components(separatedBy: "/")
            if let adobeIndex = components.firstIndex(of: "adobe"),
               adobeIndex + 1 < components.count {
                let sub = components[adobeIndex + 1]
                if identity.appName.lowercased().contains(sub.lowercased()) ||
                   sub.lowercased().contains(identity.appName.lowercased()) {
                    evidence.append(ArtifactEvidence(source: .rule, weight: 60))
                }
            }
        }

        return evidence
    }
}
