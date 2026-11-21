import Foundation

public actor PlistContentCache {
    private var cache: [String: String] = [:]
    private let maxEntries = 512

    public init() {}

    public func getContent(url: URL) async -> String? {
        let key = url.standardizedFileURL.path
        if let cached = cache[key] { return cached }

        let decoded: String? = autoreleasepool {
            do {
                let data = try Data(contentsOf: url)
                var format = PropertyListSerialization.PropertyListFormat.xml
                let plist = try PropertyListSerialization.propertyList(from: data, format: &format)
                let serialized = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                return String(data: serialized, encoding: .utf8)
            } catch {
                return nil
            }
        }
        guard let str = decoded else { return nil }
        if cache.count >= maxEntries {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = str
        return str
    }
}
