import Foundation

public struct ScoringWeights: Sendable, Equatable {
    public var bundleIDExact: Int = 100
    public var bundleIDPrefix: Int = 90
    public var appNameExact: Int = 60
    public var appNamePrefix: Int = 50
    public var executableName: Int = 70
    public var frameworkName: Int = 60
    public var xpcServiceName: Int = 50
    public var plugInName: Int = 40
    public var vendorName: Int = 30

    public var teamID: Int = 50
    public var developerSignature: Int = 40

    public var launchAgent: Int = 70
    public var launchDaemon: Int = 70
    public var loginItem: Int = 90
    public var appGroup: Int = 70
    public var container: Int = 70
    public var `extension`: Int = 70
    public var xpcConnection: Int = 60

    public var packageReceipt: Int = 100
    public var plistContent: Int = 80

    public var spotlight: Int = 5
    public var spotlightBundleAttr: Int = 100
    public var spotlightCreator: Int = 50

    public var fileContent: Int = 60
    public var electronCache: Int = 40
    public var jetBrainsConfig: Int = 60
    public var flutterBuild: Int = 50

    public var parentDirectory: Int = 25

    public var launchServicesRegistered: Int = 50

    public static let `default` = ScoringWeights()
    public static let test = ScoringWeights()

    public init() {}

    public func weight(for evidence: Evidence) -> Int {
        switch evidence {
        case .bundleIDExact: return bundleIDExact
        case .bundleIDPrefix: return bundleIDPrefix
        case .appNameExact: return appNameExact
        case .appNamePrefix: return appNamePrefix
        case .executableName: return executableName
        case .frameworkName: return frameworkName
        case .xpcServiceName: return xpcServiceName
        case .plugInName: return plugInName
        case .vendorName: return vendorName
        case .teamID: return teamID
        case .developerSignature: return developerSignature
        case .launchAgent: return launchAgent
        case .launchDaemon: return launchDaemon
        case .loginItem: return loginItem
        case .appGroup: return appGroup
        case .container: return container
        case .extension: return self.extension
        case .xpcConnection: return xpcConnection
        case .packageReceipt: return packageReceipt
        case .plistContent: return plistContent
        case .spotlight: return spotlight
        case .spotlightBundleAttr: return spotlightBundleAttr
        case .spotlightCreator: return spotlightCreator
        case .fileContent: return fileContent
        case .electronCache: return electronCache
        case .jetBrainsConfig: return jetBrainsConfig
        case .flutterBuild: return flutterBuild
        case .parentDirectory: return parentDirectory
        case .launchServicesRegistered: return launchServicesRegistered
        }
    }

    public func score(_ evidence: Set<Evidence>) -> Int {
        evidence.reduce(0) { $0 + weight(for: $1) }
    }
}
