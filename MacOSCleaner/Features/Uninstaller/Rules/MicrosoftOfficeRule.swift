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
        let bid = identity.bundleID.lowercased()
        var evidence: [ArtifactEvidence] = []

        // Suite / updater / OneDrive shared roots — never boost (registry marks shared).
        let sharedFragments = [
            "ubf8t346g9.office",
            "ubf8t346g9.onedrivestandalonesuite",
            "/application support/microsoft office",
            "/caches/com.microsoft.autoupdate",
            "/launchdaemons/com.microsoft.autoupdate",
            "/privilegedhelpertools/com.microsoft.autoupdate",
            "/application support/microsoft/mau2.0",
        ]
        if sharedFragments.contains(where: { path.contains($0) }) {
            return []
        }

        // Only score paths owned by THIS bundle ID — never broad com.microsoft.*.
        guard !bid.isEmpty else { return [] }

        if path.contains("/preferences/\(bid)") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/\(bid)") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/containers/\(bid)") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/saved application state/\(bid)") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.contains("/httpstorages/\(bid)") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/logs/\(bid)") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 40))
        }

        // App-specific Microsoft/<App> support folder (not suite root).
        let appToken = identity.appName.lowercased()
            .replacingOccurrences(of: "microsoft ", with: "")
            .trimmingCharacters(in: .whitespaces)
        if !appToken.isEmpty,
           path.contains("/application support/microsoft/\(appToken)") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if bid.contains("teams"), path.contains("/application support/microsoft/teams") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }

        return evidence
    }
}
