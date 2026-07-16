import Foundation

extension FileManager {

    /// Known VM/container directory names to exclude from size calculation.
    public static let excludedDirectoryNames: Set<String> = [
        ".dev.orbstack",
        ".orbstack",
        ".lima",
        ".colima",
        "CoreSimulator",
        "multipassd",
        "rancher-desktop",
    ]

    /// Known large sparse file names to exclude (by exact filename, not extension).
    public static let excludedFileNames: Set<String> = [
        "Docker.raw",
        "Docker.qcow2",
        "data.img.raw",
    ]

    /// File extensions to exclude (safe — always VM/disk images, never user data).
    /// `.img`, `.raw`, `.qcow2` are NOT here — they cause false positives
    /// with Android Studio AVDs and SDK system images. Those are matched by
    /// their `.avd` extension (whole directory skipped) or specific filenames.
    public static let excludedExtensions: Set<String> = [
        "dmg",
        "sparseimage",
        "sparsebundle",
        "vmdk",
        "vdi",
        "vhd",
        "vhdx",
        "hdd",
        "pvm",
        "utm",
        "avd",
    ]

    /// If logical size exceeds allocated size by this factor, the file is
    /// considered a sparse virtual disk and excluded from size calculation.
    /// Guard against unknown VM/container storage not yet in the explicit lists.
    public static let sparseFileRatioThreshold: Int = 100

    /// Flat list for code that uses `contains`-style matching.
    /// Built from the structured sets for consistency.
    public static let defaultExcludedPaths: [String] = {
        var result: [String] = []
        result.append(contentsOf: excludedExtensions.map { ".\($0)" })
        result.append(contentsOf: excludedFileNames)
        result.append(contentsOf: excludedDirectoryNames)
        return result
    }()

    nonisolated(unsafe) private static let _sizeCache = NSCache<NSString, NSNumber>()
    private static let _sizeCacheLock = NSLock()

    public nonisolated static func clearSizeCache() {
        _sizeCacheLock.lock()
        _sizeCache.removeAllObjects()
        _sizeCacheLock.unlock()
    }

    /// Checks whether a file/directory should be excluded based on structured sets.
    ///
    /// Matching priority:
    /// 1. `pathExtension` matches `excludedExtensions`
    /// 2. `lastPathComponent` matches `excludedFileNames`
    /// 3. Any ancestor directory name matches `excludedDirectoryNames`
    public static func shouldExclude(url: URL) -> Bool {
        if url.path.hasPrefix("/System") { return true }

        let ext = url.pathExtension.lowercased()
        if excludedExtensions.contains(ext) { return true }

        let lastPath = url.lastPathComponent
        if excludedFileNames.contains(lastPath) { return true }

        var parent = url.deletingLastPathComponent()
        var depth = 0
        while parent.path != "/" && depth < 10 {
            if excludedDirectoryNames.contains(where: { parent.lastPathComponent.hasSuffix($0) }) {
                return true
            }
            parent = parent.deletingLastPathComponent()
            depth += 1
        }

        return false
    }

    /// Detects sparse virtual disk files where logical size is much larger than
    /// physical allocated size. These are VM/container sparse images not yet
    /// covered by the explicit exclusion lists.
    public static func isSparseFile(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]),
              let logical = values.fileSize,
              let allocated = values.totalFileAllocatedSize,
              allocated > 0
        else { return false }
        return logical / allocated >= sparseFileRatioThreshold
    }

    public func getDirectorySize(
        url: URL,
        excludedPaths: [String] = FileManager.defaultExcludedPaths
    ) -> Int64 {
        let path = url.path
        FileManager._sizeCacheLock.lock()
        if let cached = FileManager._sizeCache.object(forKey: path as NSString) {
            FileManager._sizeCacheLock.unlock()
            return cached.int64Value
        }
        FileManager._sizeCacheLock.unlock()

        var size: Int64 = 0
        let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey],
            options: []
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            let shouldExclude: Bool
            if excludedPaths.isEmpty {
                shouldExclude = false
            } else if excludedPaths == FileManager.defaultExcludedPaths {
                shouldExclude = FileManager.shouldExclude(url: fileURL)
            } else {
                let filePath = fileURL.path
                shouldExclude = excludedPaths.contains { filePath.contains($0) }
            }
            if shouldExclude {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]),
                  let fileSize = values.fileSize else { continue }

            if let allocated = values.totalFileAllocatedSize, allocated > 0,
               fileSize / allocated >= FileManager.sparseFileRatioThreshold {
                continue
            }

            size += Int64(fileSize)
        }

        FileManager._sizeCacheLock.lock()
        FileManager._sizeCache.setObject(NSNumber(value: size), forKey: path as NSString)
        FileManager._sizeCacheLock.unlock()

        return size
    }

    public func getPhysicalDirectorySize(
        url: URL,
        excludedPaths: [String] = FileManager.defaultExcludedPaths
    ) -> Int64 {
        var size: Int64 = 0
        let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey],
            options: []
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            let shouldExclude: Bool
            if excludedPaths.isEmpty {
                shouldExclude = false
            } else if excludedPaths == FileManager.defaultExcludedPaths {
                shouldExclude = FileManager.shouldExclude(url: fileURL)
            } else {
                let filePath = fileURL.path
                shouldExclude = excludedPaths.contains { filePath.contains($0) }
            }
            if shouldExclude {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator?.skipDescendants()
                }
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]),
                  let fileSize = values.fileSize else { continue }

            if let allocated = values.totalFileAllocatedSize, allocated > 0,
               fileSize / allocated >= FileManager.sparseFileRatioThreshold {
                continue
            }

            if let allocated = values.totalFileAllocatedSize {
                size += Int64(allocated)
            } else {
                size += Int64(fileSize)
            }
        }
        return size
    }
}
