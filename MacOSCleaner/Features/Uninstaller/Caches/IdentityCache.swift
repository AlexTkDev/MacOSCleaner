import Foundation

public actor IdentityCache {
    private var cache: [String: AppIdentity] = [:]

    public init() {}

    public func get(bundleID: String) -> AppIdentity? {
        cache[bundleID]
    }

    public func set(bundleID: String, identity: AppIdentity) {
        cache[bundleID] = identity
    }
}
