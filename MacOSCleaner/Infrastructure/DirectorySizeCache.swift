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
        FileManager.clearSizeCache()
    }

    public func invalidateParent(of path: String) {
        let parent = (path as NSString).deletingLastPathComponent
        cache.removeValue(forKey: parent)
        FileManager.clearSizeCache()
    }

    public func invalidateAll() {
        cache.removeAll()
        FileManager.clearSizeCache()
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

    /// Reclaimable disk footprint (allocated blocks), not logical/apparent size.
    /// APFS clones in DerivedData can report tens of GB logical while only
    /// hundreds of MB are actually freed on delete.
    private func computeSize(_ path: String) -> CachedDirectoryInfo {
        let url = URL(fileURLWithPath: path)
        var size: Int64 = 0
        var fileCount: Int = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey],
            options: []
        ) else { return CachedDirectoryInfo(size: 0, fileCount: 0, timestamp: Date()) }

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled {
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
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else {
                continue
            }
            // Prefer allocated (physical) size — what deleting actually reclaims.
            // Use allocated even when 0 (true sparse files); only fall back if key missing.
            if let allocated = values.totalFileAllocatedSize {
                size += Int64(allocated)
            } else if let fileSize = values.fileSize {
                size += Int64(fileSize)
            }
        }
        return CachedDirectoryInfo(size: size, fileCount: fileCount, timestamp: Date())
    }
}
