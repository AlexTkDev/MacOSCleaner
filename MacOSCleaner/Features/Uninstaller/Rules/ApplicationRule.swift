import Foundation

public protocol ApplicationRule: Sendable {
    var displayName: String { get }
    var supportedBundleIDs: Set<String> { get }
    var supportedTeamIDs: Set<String> { get }
    var supportedAppNames: Set<String> { get }
    func matches(identity: AppIdentity) -> Bool
    func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence]
}

extension ApplicationRule {
    public func matches(identity: AppIdentity) -> Bool {
        if supportedBundleIDs.contains(identity.bundleID) { return true }
        if let tid = identity.teamID, supportedTeamIDs.contains(tid) { return true }
        if supportedAppNames.contains(identity.appName) { return true }
        let lower = identity.appName.lowercased()
        return supportedAppNames.contains { lower.contains($0.lowercased()) }
    }
}
