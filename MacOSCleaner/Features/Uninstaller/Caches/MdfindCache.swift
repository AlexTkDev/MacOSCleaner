import Foundation

public actor MdfindCache {
    private var cache: [String: Set<URL>] = [:]

    public init() {}

    public func get(query: String) -> Set<URL>? {
        cache[query]
    }

    public func set(query: String, results: Set<URL>) {
        cache[query] = NormalizedPath.urls(results)
    }
}
