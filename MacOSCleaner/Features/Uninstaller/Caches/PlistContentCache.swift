import Foundation

public actor PlistContentCache {
    private var cache: [String: String] = [:]

    public init() {}

    public func getContent(url: URL) async -> String? {
        let key = url.standardizedFileURL.path
        if let cached = cache[key] { return cached }

        do {
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.xml
            let plist = try PropertyListSerialization.propertyList(from: data, format: &format)
            let serialized = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            if let str = String(data: serialized, encoding: .utf8) {
                cache[key] = str
                return str
            }
        } catch {
            cache[key] = ""
        }
        return nil
    }
}
