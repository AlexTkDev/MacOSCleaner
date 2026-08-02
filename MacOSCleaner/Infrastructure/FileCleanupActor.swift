import Foundation
import OSLog

private extension Logger {
    static let fileActor = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "FileCleanupActor")
}

public actor FileCleanupActor {
    private let safetyManager: SafetyManager
    private let sizeCache: DirectorySizeCache
    private let fileSystemContext: FileSystemContext
    private let fm = FileManager.default

    /// Skip scan preview for items that reclaim nothing meaningful on disk.
    private static let minPreviewBytes: Int64 = 1024

    public init(
        safetyManager: SafetyManager = SafetyManager(),
        sizeCache: DirectorySizeCache = DirectorySizeCache(),
        fileSystemContext: FileSystemContext = .production
    ) {
        self.safetyManager = safetyManager
        self.sizeCache = sizeCache
        self.fileSystemContext = fileSystemContext
    }

    func getDirectorySize(_ path: String) async -> Int64 {
        await sizeCache.getSize(for: path)
    }

    func cleanContents(of path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        try Task.checkCancellation()
        let url = URL(fileURLWithPath: path)
        try fileSystemContext.assertAllowedForMutation(url)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }

        // Do not traverse into symlink directories — leaf symlink is removed as the link itself.
        if safetyManager.isSymlinkDirectory(url) {
            progress?(.log("  \(Self.shortPath(path)) — symlink directory, skipped"))
            return (0, nil)
        }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: path, isDirectory: &isDir)

        if !isDir.boolValue {
            let size = Self.physicalSize(of: path, fm: fm)
            if dryRun {
                progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(size))"))
                guard size >= Self.minPreviewBytes else { return (0, nil) }
                return (size, Self.fileItemForPath(path, size: size, isDirectory: false))
            }
            do {
                try fm.removeItem(at: url)
            } catch {
                progress?(.log("  \(Self.shortPath(path)) — delete failed: \(error.localizedDescription)"))
                Logger.fileActor.error("Delete failed \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return (0, nil)
            }
            guard !fm.fileExists(atPath: path) else {
                progress?(.log("  \(Self.shortPath(path)) — still present after delete, not counting"))
                return (0, nil)
            }
            progress?(.log("  \(Self.shortPath(path)) — removed, freed \(Self.formatBytes(size))"))
            return (size, nil)
        }

        let before = await getDirectorySize(path)
        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(before))"))
            guard before >= Self.minPreviewBytes else { return (0, nil) }
            return (before, Self.fileItemForPath(path, size: before, isDirectory: true))
        }

        let contents = try fm.contentsOfDirectory(atPath: path)
        var removedCount = 0
        var failedCount = 0
        let runningBundle = Bundle.main.bundlePath
        for item in contents {
            try Task.checkCancellation()
            let itemURL = url.appendingPathComponent(item)
            // Never delete the live app / test host (e.g. DerivedData/.../MacOSCleaner.app).
            if Self.pathContainsRunningBundle(itemURL.path, bundlePath: runningBundle) {
                progress?(.log("  \(Self.shortPath(itemURL.path)) — running app, skipped"))
                continue
            }
            // Skip symlink directories; leaf symlinks are removed as links (validate allows them).
            if safetyManager.isSymlinkDirectory(itemURL) {
                progress?(.log("  \(Self.shortPath(itemURL.path)) — symlink directory, skipped"))
                continue
            }
            guard (try? safetyManager.validate(url: itemURL)) != nil else {
                progress?(.log("  \(Self.shortPath(itemURL.path)) — protected, skipped"))
                continue
            }
            do {
                try fileSystemContext.assertAllowedForMutation(itemURL)
                try fm.removeItem(at: itemURL)
                removedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedCount += 1
                progress?(.log("  \(Self.shortPath(itemURL.path)) — delete failed: \(error.localizedDescription)"))
                Logger.fileActor.error("Delete failed \(itemURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        await sizeCache.invalidate(path)
        let after = await getDirectorySize(path)
        let freed = max(0, before - after)
        if failedCount > 0 {
            progress?(.log("  \(Self.shortPath(path)) — removed \(removedCount), failed \(failedCount), freed \(Self.formatBytes(freed))"))
        } else if freed > 0 {
            progress?(.log("  \(Self.shortPath(path)) — removed \(removedCount) items, freed \(Self.formatBytes(freed))"))
        }
        return (freed, nil)
    }

    func removeDirectory(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }

        if Self.pathContainsRunningBundle(path, bundlePath: Bundle.main.bundlePath) {
            progress?(.log("  \(Self.shortPath(path)) — running app, skipped"))
            return (0, nil)
        }

        let before = await getDirectorySize(path)

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(before))"))
            guard before >= Self.minPreviewBytes else { return (0, nil) }
            return (before, Self.fileItemForPath(path, size: before, isDirectory: true))
        }

        do {
            try fm.removeItem(atPath: path)
        } catch {
            progress?(.log("  \(Self.shortPath(path)) — delete failed: \(error.localizedDescription)"))
            Logger.fileActor.error("Delete failed \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return (0, nil)
        }
        await sizeCache.invalidate(path)
        guard !fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — still present after delete, not counting"))
            return (0, nil)
        }
        progress?(.log("  \(Self.shortPath(path)) — removed, freed \(Self.formatBytes(before))"))
        return (before, nil)
    }

    func removeFile(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let size = Self.physicalSize(of: path, fm: fm)
        let attrs = try? fm.attributesOfItem(atPath: path)

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(size))"))
            guard size >= Self.minPreviewBytes else { return (0, nil) }
            let modDate = attrs?[.modificationDate] as? Date
            let item = CleanupFileItem(path: path, sizeBytes: size, modificationDate: modDate, isDirectory: false)
            return (size, item)
        }

        do {
            try fm.removeItem(atPath: path)
        } catch {
            progress?(.log("  \(Self.shortPath(path)) — delete failed: \(error.localizedDescription)"))
            Logger.fileActor.error("Delete failed \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return (0, nil)
        }
        guard !fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — still present after delete, not counting"))
            return (0, nil)
        }
        progress?(.log("  \(Self.shortPath(path)) — removed, freed \(Self.formatBytes(size))"))
        return (size, nil)
    }

    func cleanOldFiles(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var freed: Int64 = 0
        var removedCount = 0

        let contents = try fm.contentsOfDirectory(atPath: path)
        for item in contents {
            let itemURL = URL(fileURLWithPath: path).appendingPathComponent(item)
            let attrs = try? fm.attributesOfItem(atPath: itemURL.path)
            if let modDate = attrs?[.modificationDate] as? Date, modDate < cutoffDate {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: itemURL.path, isDirectory: &isDir)
                let size: Int64
                if isDir.boolValue {
                    size = await getDirectorySize(itemURL.path)
                } else {
                    size = Self.physicalSize(of: itemURL.path, fm: fm)
                }
                if dryRun {
                    freed += size
                    removedCount += 1
                } else {
                    do {
                        try fm.removeItem(at: itemURL)
                        guard !fm.fileExists(atPath: itemURL.path) else { continue }
                        freed += size
                        removedCount += 1
                    } catch {
                        progress?(.log("  \(Self.shortPath(itemURL.path)) — delete failed: \(error.localizedDescription)"))
                    }
                }
            }
        }
        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(removedCount) items older than \(days) days (\(Self.formatBytes(freed)))"))
            guard freed >= Self.minPreviewBytes else { return (0, nil) }
            return (freed, Self.fileItemForPath(path, size: freed, isDirectory: true))
        } else {
            progress?(.log("  \(Self.shortPath(path)) — removed \(removedCount) old items, freed \(Self.formatBytes(freed))"))
        }
        return (freed, nil)
    }

    func cleanOldFilesRecursive(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var freed: Int64 = 0
        var removedCount = 0

        guard let enumerator = fm.enumerator(atPath: path) else { return (0, nil) }
        while let item = enumerator.nextObject() as? String {
            try Task.checkCancellation()
            let itemPath = "\(path)/\(item)"
            let itemURL = URL(fileURLWithPath: itemPath)
            let shouldExclude = FileManager.shouldExclude(url: itemURL)
            if shouldExclude {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: itemPath, isDirectory: &isDir)
                if isDir.boolValue { enumerator.skipDescendants() }
                continue
            }
            let attrs = try? fm.attributesOfItem(atPath: itemPath)
            if let modDate = attrs?[.modificationDate] as? Date, modDate < cutoffDate {
                let size = Self.physicalSize(of: itemPath, fm: fm)
                if dryRun {
                    freed += size
                    removedCount += 1
                } else {
                    do {
                        try fm.removeItem(atPath: itemPath)
                        guard !fm.fileExists(atPath: itemPath) else { continue }
                        freed += size
                        removedCount += 1
                    } catch {
                        progress?(.log("  \(Self.shortPath(itemPath)) — delete failed: \(error.localizedDescription)"))
                    }
                }
            }
        }

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(removedCount) items older than \(days) days (\(Self.formatBytes(freed)))"))
            guard freed >= Self.minPreviewBytes else { return (0, nil) }
            return (freed, Self.fileItemForPath(path, size: freed, isDirectory: true))
        } else {
            progress?(.log("  \(Self.shortPath(path)) — removed \(removedCount) old items, freed \(Self.formatBytes(freed))"))
        }
        return (freed, nil)
    }

    func cleanContentsParallel(_ paths: [String], dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> Int64 {
        var totalFreed: Int64 = 0
        for path in paths {
            try Task.checkCancellation()
            let (freed, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            totalFreed += freed
            if dryRun, let item { emitFileItem(item, category: nil, parentName: nil, progress: progress) }
        }
        return totalFreed
    }

    func emitFileItem(_ item: CleanupFileItem?, category: String?, parentName: String?, progress: (@Sendable (CleanupEngineEvent) -> Void)?) {
        guard let item, item.sizeBytes >= Self.minPreviewBytes else { return }
        progress?(.fileItem(
            path: item.path,
            sizeBytes: item.sizeBytes,
            modificationDate: item.modificationDate,
            isDirectory: item.isDirectory,
            category: category ?? "",
            parentName: parentName
        ))
    }

    static func fileItemForPath(_ path: String, size: Int64, isDirectory: Bool) -> CleanupFileItem? {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let modDate = attrs?[.modificationDate] as? Date
        return CleanupFileItem(path: path, sizeBytes: size, modificationDate: modDate, isDirectory: isDirectory)
    }

    /// Physical allocated size for a single file (or directory via getDirectorySize).
    static func physicalSize(of path: String, fm: FileManager) -> Int64 {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
            if let allocated = values.totalFileAllocatedSize {
                return Int64(allocated)
            }
            if let fileSize = values.fileSize {
                return Int64(fileSize)
            }
        }
        return (try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return String(format: "format_bytes_b".localized, bytes) }
        if bytes < 1024 * 1024 { return String(format: "format_bytes_kb".localized, Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "format_bytes_mb".localized, Double(bytes) / (1024 * 1024)) }
        return String(format: "format_bytes_gb".localized, Double(bytes) / (1024 * 1024 * 1024))
    }

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
    }

    /// True when `path` is the running bundle or an ancestor/descendant of it.
    static func pathContainsRunningBundle(_ path: String, bundlePath: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        let b = URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        guard !b.isEmpty else { return false }
        return p == b || b.hasPrefix(p + "/") || p.hasPrefix(b + "/")
    }
}
