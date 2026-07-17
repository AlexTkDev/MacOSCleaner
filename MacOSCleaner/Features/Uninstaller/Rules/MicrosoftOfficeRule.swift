import Foundation

public struct MicrosoftOfficeRule: ApplicationRule {
    public let displayName = "Microsoft Office"
    public let supportedBundleIDs: Set<String> = [
        "com.microsoft.word",
        "com.microsoft.excel",
        "com.microsoft.powerpoint",
        "com.microsoft.outlook",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.microsoft.onenote.mac",
        "com.microsoft.Excel",
        "com.microsoft.Word",
        "com.microsoft.Powerpoint",
        "com.microsoft.autoupdate2",
        "com.microsoft.autoupdate",
        "com.microsoft.autoupdate.fba",
    ]
    public let supportedTeamIDs: Set<String> = [
        "UBF8T346G9",
    ]
    public let supportedAppNames: Set<String> = [
        "Microsoft Word", "Word",
        "Microsoft Excel", "Excel",
        "Microsoft PowerPoint", "PowerPoint",
        "Microsoft Outlook", "Outlook",
        "Microsoft Teams", "Teams",
        "Microsoft OneNote", "OneNote",
        "Microsoft AutoUpdate", "Microsoft Office",
    ]

    public init() {}

    public func matches(identity: AppIdentity) -> Bool {
        if supportedBundleIDs.contains(identity.bundleID) { return true }
        if let tid = identity.teamID, supportedTeamIDs.contains(tid) {
            let name = identity.appName.lowercased()
            if name.hasPrefix("microsoft") || name.contains("office") || name.contains("teams") {
                return true
            }
        }
        if supportedAppNames.contains(identity.appName) { return true }
        let lower = identity.appName.lowercased()
        return lower.hasPrefix("microsoft")
    }

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/application support/microsoft") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/microsoft office") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/preferences/com.microsoft.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.microsoft.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/caches/com.microsoft.autoupdate") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/containers/com.microsoft.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/group containers/ubf8t346g9.office") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/group containers/ubf8t346g9.onedrivestandalonesuite") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/logs/microsoft") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/launchdaemons/com.microsoft.autoupdate") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/privilegedhelpertools/com.microsoft.autoupdate") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/application support/microsoft/mau2.0") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/saved application state/com.microsoft.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.contains("/application support/microsoft/teams") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }

        return evidence
    }
}
