import Foundation

extension FileManager {
    /// Paths to exclude from size calculation (sparse files, virtual disks, etc.)
    public static let defaultExcludedPaths: [String] = [
        ".dev.orbstack",
        ".orbstack",
        ".dmg",
        ".sparseimage",
        ".sparsebundle",
        ".raw",
        ".qcow2",
        ".img",
        ".vmdk",
        ".vdi",
        ".vhd",
        ".vhdx",
        "Docker.raw",
        "docker.raw"
    ]

    nonisolated(unsafe) private static let _sizeCache = NSCache<NSString, NSNumber>()
    private static let _sizeCacheLock = NSLock()

    /// Clears the size cache (call after cleanup operations).
    public nonisolated static func clearSizeCache() {
        _sizeCacheLock.lock()
        _sizeCache.removeAllObjects()
        _sizeCacheLock.unlock()
    }

    public func getDirectorySize(url: URL, excludedPaths: [String] = FileManager.defaultExcludedPaths) -> Int64 {
        let path = url.path
        FileManager._sizeCacheLock.lock()
        if let cached = FileManager._sizeCache.object(forKey: path as NSString) {
            FileManager._sizeCacheLock.unlock()
            return cached.int64Value
        }
        FileManager._sizeCacheLock.unlock()

        var size: Int64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [])
        while let fileURL = enumerator?.nextObject() as? URL {
            let filePath = fileURL.path
            let shouldExclude = excludedPaths.contains { filePath.contains($0) }
            if shouldExclude {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            size += Int64(resourceValues?.fileSize ?? 0)
        }

        FileManager._sizeCacheLock.lock()
        FileManager._sizeCache.setObject(NSNumber(value: size), forKey: path as NSString)
        FileManager._sizeCacheLock.unlock()

        return size
    }

    /// Fast size estimation using filesystem allocated size (physical disk usage).
    public func getPhysicalDirectorySize(url: URL, excludedPaths: [String] = FileManager.defaultExcludedPaths) -> Int64 {
        var size: Int64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey], options: [])
        while let fileURL = enumerator?.nextObject() as? URL {
            let filePath = fileURL.path
            let shouldExclude = excludedPaths.contains { filePath.contains($0) }
            if shouldExclude {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
            let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            if let allocated = resourceValues?.totalFileAllocatedSize {
                size += Int64(allocated)
            } else {
                size += Int64(resourceValues?.fileSize ?? 0)
            }
        }
        return size
    }
}
