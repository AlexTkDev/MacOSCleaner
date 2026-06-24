import Foundation

public struct CachedDirectoryInfo: Sendable {
    public let size: Int64
    public let fileCount: Int
    public let timestamp: Date
    
    public init(size: Int64, fileCount: Int, timestamp: Date) {
        self.size = size
        self.fileCount = fileCount
        self.timestamp = timestamp
    }
    
    public var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 300 // 5 minutes TTL
    }
}

public actor DirectorySizeCache {
    private var cache: [String: CachedDirectoryInfo] = [:]
    private let fm = FileManager.default
    private let defaultTTL: TimeInterval = 300 // 5 minutes

    public init() {}

    public func getSize(for path: String) -> Int64 {
        if let cached = cache[path], !cached.isExpired { return cached.size }
        let info = computeSize(path)
        cache[path] = info
        return info.size
    }

    public func getSize(for path: String, calculator: () throws -> Int64) rethrows -> Int64 {
        if let cached = cache[path], !cached.isExpired { return cached.size }
        let size = try calculator()
        cache[path] = CachedDirectoryInfo(size: size, fileCount: 0, timestamp: Date())
        return size
    }

    public func getInfo(for path: String) -> CachedDirectoryInfo? {
        if let cached = cache[path], !cached.isExpired { return cached }
        let info = computeSize(path)
        cache[path] = info
        return info
    }

    public func invalidate(_ path: String) {
        cache.removeValue(forKey: path)
    }

    public func invalidateParent(of path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        cache.removeValue(forKey: parent)
    }

    public func invalidateAll() {
        cache.removeAll()
    }

    public func getCachedSize(_ path: String) -> Int64? {
        cache[path]?.size
    }

    public func preload(paths: [String]) {
        for path in paths {
            guard !path.isEmpty else { continue }
            if let cached = cache[path], !cached.isExpired { continue }
            let info = computeSize(path)
            cache[path] = info
        }
    }

    private func computeSize(_ path: String) -> CachedDirectoryInfo {
        let url = URL(fileURLWithPath: path)
        var size: Int64 = 0
        var fileCount: Int = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else { return CachedDirectoryInfo(size: 0, fileCount: 0, timestamp: Date()) }

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                break
            }
            if fileCount >= 100000 {
                // Prevent infinite or extremely long size calculations
                break
            }
            let shouldExclude = FileManager.shouldExclude(url: fileURL)
            if shouldExclude {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            fileCount += 1
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]) {
                size += Int64(values.fileSize ?? 0)
            }
        }
        return CachedDirectoryInfo(size: size, fileCount: fileCount, timestamp: Date())
    }
}
