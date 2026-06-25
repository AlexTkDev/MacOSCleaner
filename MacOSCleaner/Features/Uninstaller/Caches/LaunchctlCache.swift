import Foundation

public actor LaunchctlCache {
    private var cache: [String: String] = [:]

    public init() {}

    public func getPlistContent(for url: URL) async -> String? {
        let key = url.standardizedFileURL.path
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }
        do {
            let data = try Data(contentsOf: url)
            let content = String(decoding: data, as: UTF8.self)
            cache[key] = content
            return content
        } catch {
            cache[key] = ""
            return nil
        }
    }

    public func clear() { cache.removeAll() }
}
