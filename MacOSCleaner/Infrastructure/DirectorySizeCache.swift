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
    private var inFlight: [String: Task<CachedDirectoryInfo, Never>] = [:]

    public init() {}

    public func getSize(for path: String) async -> Int64 {
        if let cached = cache[path], !cached.isExpired { return cached.size }
        if let existing = inFlight[path] {
            return await existing.value.size
        }

        // Run enumeration off the actor executor so concurrent categories do not serialize on one lock.
        let task = Task.detached(priority: .utility) {
            Self.computeSize(path)
        }
        inFlight[path] = task
        let info = await task.value
        inFlight.removeValue(forKey: path)

        if Task.isCancelled { return info.size }
        cache[path] = info
        return info.size
    }

    public func invalidate(_ path: String) {
        cache.removeValue(forKey: path)
        inFlight[path]?.cancel()
        inFlight.removeValue(forKey: path)
        FileManager.clearSizeCache()
    }

    /// Reclaimable disk footprint (allocated blocks), not logical/apparent size.
    /// APFS clones in DerivedData can report tens of GB logical while only
    /// hundreds of MB are actually freed on delete.
    private nonisolated static func computeSize(_ path: String) -> CachedDirectoryInfo {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        var size: Int64 = 0
        var fileCount: Int = 0
        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isDirectoryKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
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
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }
            if FileManager.isNotDownloadedUbiquitous(values) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            fileCount += 1
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
