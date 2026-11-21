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

    nonisolated(unsafe) private static let _sizeCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 4096
        return cache
    }()
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

    /// True when the item is an iCloud dataless placeholder whose contents must not be read or materialized.
    public static func isNotDownloadedUbiquitous(_ values: URLResourceValues) -> Bool {
        values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded
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
        var cancelled = false
        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isRegularFileKey,
            .isDirectoryKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )
        var batchCount = 0
        var stopEnumerating = false
        while !stopEnumerating {
            autoreleasepool {
                batchCount = 0
                while batchCount < 256 {
                    guard let fileURL = enumerator?.nextObject() as? URL else {
                        stopEnumerating = true
                        break
                    }
                    batchCount += 1
                    if Task.isCancelled {
                        cancelled = true
                        stopEnumerating = true
                        break
                    }
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

                    guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                        continue
                    }
                    if FileManager.isNotDownloadedUbiquitous(values) {
                        if values.isDirectory == true { enumerator?.skipDescendants() }
                        continue
                    }

                    if let fileSize = values.fileSize,
                       let allocated = values.totalFileAllocatedSize, allocated > 0,
                       fileSize / allocated >= FileManager.sparseFileRatioThreshold {
                        continue
                    }

                    // Prefer allocated (physical) size — APFS clones inflate logical fileSize.
                    // allocated == 0 is valid for sparse files; only fall back if key is missing.
                    if let allocated = values.totalFileAllocatedSize {
                        size += Int64(allocated)
                    } else if let fileSize = values.fileSize {
                        size += Int64(fileSize)
                    }
                }
            }
        }

        guard !cancelled else { return size }

        FileManager._sizeCacheLock.lock()
        FileManager._sizeCache.setObject(NSNumber(value: size), forKey: path as NSString)
        FileManager._sizeCacheLock.unlock()

        return size
    }

    /// Physical (allocated) size — the disk space actually freed when the item is
    /// deleted. Sparse VM images (OrbStack data.img.raw: 494 GB logical / 44 GB
    /// allocated) are counted by their real footprint, never the logical size.
    /// Works for single files as well as directories.
    public func getPhysicalDirectorySize(
        url: URL,
        excludedPaths: [String] = FileManager.defaultExcludedPaths
    ) -> Int64 {
        let rootPath = url.path
        let cacheKey = "physical:\(rootPath)" as NSString
        FileManager._sizeCacheLock.lock()
        if let cached = FileManager._sizeCache.object(forKey: cacheKey) {
            FileManager._sizeCacheLock.unlock()
            return cached.int64Value
        }
        FileManager._sizeCacheLock.unlock()

        var rootStat = Darwin.stat()
        if stat(rootPath, &rootStat) != 0 {
            if lstat(rootPath, &rootStat) != 0 {
                return 0
            }
        }

        if (rootStat.st_flags & UInt32(SF_DATALESS)) != 0 {
            return 0
        }

        if (rootStat.st_mode & S_IFMT) != S_IFDIR {
            let size = Int64(rootStat.st_blocks) * 512
            if !Task.isCancelled {
                FileManager._sizeCacheLock.lock()
                FileManager._sizeCache.setObject(NSNumber(value: size), forKey: cacheKey)
                FileManager._sizeCacheLock.unlock()
            }
            return size
        }

        let useDefaultExclusions = excludedPaths == FileManager.defaultExcludedPaths
        let customExcluded = useDefaultExclusions ? [] : excludedPaths
        let isSystemRoot = useDefaultExclusions && rootPath.hasPrefix("/System")
        if isSystemRoot {
            return 0
        }

        var size: Int64 = 0
        var cancelled = false
        var visitedDirInodes = Set<UInt64>()
        var stack: [String] = [rootPath]
        var checkCounter = 0

        while let currentDir = stack.popLast() {
            if Task.isCancelled {
                cancelled = true
                break
            }
            guard let dir = opendir(currentDir) else { continue }
            let fd = dirfd(dir)

            var dirStat = Darwin.stat()
            if fstat(fd, &dirStat) == 0 {
                if (dirStat.st_flags & UInt32(SF_DATALESS)) != 0 {
                    closedir(dir)
                    continue
                }
                if !visitedDirInodes.insert(dirStat.st_ino).inserted {
                    closedir(dir)
                    continue
                }
            }

            while let entry = readdir(dir) {
                checkCounter &+= 1
                if (checkCounter & 63) == 0, Task.isCancelled {
                    cancelled = true
                    break
                }

                let isDot = withUnsafePointer(to: &entry.pointee.d_name) { ptr -> Bool in
                    let cPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                    if cPtr[0] == 46 { // '.'
                        if cPtr[1] == 0 { return true }
                        if cPtr[1] == 46 && cPtr[2] == 0 { return true }
                    }
                    return false
                }
                if isDot { continue }

                let name = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                let childPath = currentDir == "/" ? "/\(name)" : "\(currentDir)/\(name)"

                var childStat = Darwin.stat()
                let statOK = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                    let cPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                    return fstatat(fd, cPtr, &childStat, AT_SYMLINK_NOFOLLOW) == 0
                }
                guard statOK else { continue }

                if (childStat.st_flags & UInt32(SF_DATALESS)) != 0 {
                    continue
                }

                let fileType = childStat.st_mode & S_IFMT
                let isDir = fileType == S_IFDIR

                if !excludedPaths.isEmpty {
                    if useDefaultExclusions {
                        if Self.shouldExcludePOSIXEntry(
                            name: name,
                            fullPath: childPath,
                            isDirectory: isDir
                        ) {
                            continue
                        }
                    } else if customExcluded.contains(where: { childPath.contains($0) }) {
                        continue
                    }
                }

                if isDir {
                    stack.append(childPath)
                } else if fileType == S_IFREG || fileType == S_IFLNK {
                    size += Int64(childStat.st_blocks) * 512
                }
            }

            closedir(dir)
            if cancelled { break }
        }

        guard !cancelled else { return size }

        FileManager._sizeCacheLock.lock()
        FileManager._sizeCache.setObject(NSNumber(value: size), forKey: cacheKey)
        FileManager._sizeCacheLock.unlock()
        return size
    }

    private static func shouldExcludePOSIXEntry(name: String, fullPath: String, isDirectory: Bool) -> Bool {
        if fullPath.hasPrefix("/System") { return true }
        if let dotIndex = name.lastIndex(of: "."), dotIndex < name.index(before: name.endIndex) {
            let ext = name[name.index(after: dotIndex)...].lowercased()
            if excludedExtensions.contains(ext) { return true }
        }
        if excludedFileNames.contains(name) { return true }
        if isDirectory, excludedDirectoryNames.contains(where: { name.hasSuffix($0) }) {
            return true
        }
        return false
    }
}
