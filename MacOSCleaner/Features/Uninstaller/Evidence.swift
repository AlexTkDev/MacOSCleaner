import Foundation

public enum Evidence: String, Sendable, Hashable, CaseIterable {
    case bundleIDExact
    case bundleIDPrefix
    case appNameExact
    case appNamePrefix
    case executableName
    case frameworkName
    case xpcServiceName
    case plugInName
    case vendorName

    case teamID
    case developerSignature

    case launchAgent
    case launchDaemon
    case loginItem
    case appGroup
    case container
    case `extension`
    case xpcConnection

    case packageReceipt
    case knownCatalog
    case plistContent

    case spotlight
    case spotlightBundleAttr
    case spotlightCreator

    case fileContent
    case electronCache
    case jetBrainsConfig
    case flutterBuild

    case parentDirectory

    case launchServicesRegistered
}

public enum EvidenceCategory: String, Sendable, Hashable, CaseIterable {
    case identity
    case signature
    case system
    case metadata
    case content
    case graph
    case launchServices
}

public extension Evidence {
    var category: EvidenceCategory {
        switch self {
        case .bundleIDExact, .bundleIDPrefix, .appNameExact, .appNamePrefix,
             .executableName, .frameworkName, .xpcServiceName,
             .plugInName, .vendorName:
            return .identity
        case .teamID, .developerSignature:
            return .signature
        case .launchAgent, .launchDaemon, .loginItem,
             .appGroup, .container, .extension, .xpcConnection:
            return .system
        case .packageReceipt, .knownCatalog, .plistContent:
            return .metadata
        case .spotlight, .spotlightBundleAttr, .spotlightCreator:
            return .content
        case .fileContent, .electronCache, .jetBrainsConfig, .flutterBuild:
            return .content
        case .parentDirectory:
            return .graph
        case .launchServicesRegistered:
            return .launchServices
        }
    }
}
