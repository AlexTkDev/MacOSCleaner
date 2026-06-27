import Foundation
import OSLog

private extension Logger {
    static let fileActor = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "FileCleanupActor")
}

public actor FileCleanupActor {
    private let safetyManager: SafetyManager
    private let sizeCache: DirectorySizeCache
    private let fm = FileManager.default

    public init(safetyManager: SafetyManager = SafetyManager(), sizeCache: DirectorySizeCache = DirectorySizeCache()) {
        self.safetyManager = safetyManager
        self.sizeCache = sizeCache
    }

    func getDirectorySize(_ path: String) async -> Int64 {
        await sizeCache.getSize(for: path)
    }

    func cleanContents(of path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: path, isDirectory: &isDir)

        if !isDir.boolValue {
            let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            if dryRun {
                progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(size))"))
                return (size, Self.fileItemForPath(path))
            }
            try? fm.removeItem(at: url)
            progress?(.log("  \(Self.shortPath(path)) — removed, freed \(Self.formatBytes(size))"))
            return (size, nil)
        }

        let before = await getDirectorySize(path)
        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(before))"))
            return (before, Self.fileItemForPath(path))
        }

        let contents = try fm.contentsOfDirectory(atPath: path)
        var removedCount = 0
        for item in contents {
            let itemURL = url.appendingPathComponent(item)
            try? fm.removeItem(at: itemURL)
            removedCount += 1
        }

        await sizeCache.invalidate(path)
        let after = await getDirectorySize(path)
        let freed = max(0, before - after)
        if freed > 0 {
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
        let before = await getDirectorySize(path)

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(before))"))
            return (before, Self.fileItemForPath(path))
        }

        try? fm.removeItem(atPath: path)
        await sizeCache.invalidate(path)
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
        let attrs = try fm.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int64) ?? 0

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(size))"))
            let modDate = attrs[.modificationDate] as? Date
            let item = CleanupFileItem(path: path, sizeBytes: size, modificationDate: modDate, isDirectory: false)
            return (size, item)
        }

        try? fm.removeItem(atPath: path)
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
                    size = (attrs?[.size] as? Int64) ?? 0
                }
                if !dryRun { try? fm.removeItem(at: itemURL) }
                freed += size
                removedCount += 1
            }
        }
        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(removedCount) items older than \(days) days (\(Self.formatBytes(freed)))"))
            return (freed, Self.fileItemForPath(path))
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
                let size = (attrs?[.size] as? Int64) ?? 0
                if !dryRun { try? fm.removeItem(atPath: itemPath) }
                freed += size
                removedCount += 1
            }
        }

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(removedCount) items older than \(days) days (\(Self.formatBytes(freed)))"))
            return (freed, Self.fileItemForPath(path))
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
        guard let item else { return }
        progress?(.fileItem(
            path: item.path,
            sizeBytes: item.sizeBytes,
            modificationDate: item.modificationDate,
            isDirectory: item.isDirectory,
            category: category ?? "",
            parentName: parentName
        ))
    }

    static func fileItemForPath(_ path: String) -> CleanupFileItem? {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let modDate = attrs?[.modificationDate] as? Date
        let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
        let size: Int64
        if isDir {
            size = fm.getDirectorySize(url: URL(fileURLWithPath: path))
        } else {
            size = (attrs?[.size] as? Int64) ?? 0
        }
        return CleanupFileItem(path: path, sizeBytes: size, modificationDate: modDate, isDirectory: isDir)
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
}
