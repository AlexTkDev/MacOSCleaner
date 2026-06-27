import Foundation

public struct JetBrainsRule: ApplicationRule {
    public let displayName = "JetBrains"
    public let supportedBundleIDs: Set<String> = []
    public let supportedTeamIDs: Set<String> = ["2YEDZK7QJ8"]
    public let supportedAppNames: Set<String> = [
        "IntelliJ IDEA", "PyCharm", "GoLand", "WebStorm",
        "DataGrip", "RubyMine", "CLion", "Rider", "AppCode",
        "PhpStorm", "Aqua",
    ]

    private static let ideNameMap: [String: String] = [
        "com.jetbrains.intellij": "IntelliJIDEA",
        "com.jetbrains.pycharm": "PyCharm",
        "com.jetbrains.goland": "GoLand",
        "com.jetbrains.webstorm": "WebStorm",
        "com.jetbrains.datagrip": "DataGrip",
        "com.jetbrains.rubymine": "RubyMine",
        "com.jetbrains.clion": "CLion",
        "com.jetbrains.rider": "Rider",
        "com.jetbrains.appcode": "AppCode",
        "com.jetbrains.phpstorm": "PhpStorm",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        let ide = Self.ideName(from: identity.bundleID)?.lowercased() ?? identity.appName.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/applicationsupport/jetbrains/\(ide)") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 60))
        }
        if path.contains("/caches/jetbrains/\(ide)") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }
        if path.contains("/logs/jetbrains/\(ide)") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 40))
        }
        if path.contains("/preferences/\(ide)") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }

        return evidence
    }

    private static func ideName(from bundleID: String) -> String? {
        for (prefix, name) in ideNameMap {
            if bundleID.lowercased().hasPrefix(prefix.lowercased()) {
                return name
            }
        }
        return nil
    }
}
