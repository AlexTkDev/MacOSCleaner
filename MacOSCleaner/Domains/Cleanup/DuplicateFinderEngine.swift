// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import Foundation
import CryptoKit
import OSLog

private extension Logger {
    static let duplicateEngine = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "DuplicateFinderEngine")
}

public actor DuplicateFinderEngine {
    public enum ScanStage: Sendable, Equatable {
        case collectingFiles
        case sizeFiltering
        case headerHashing(current: Int, total: Int)
        case fullHashing(current: Int, total: Int)
        case completed
    }

    public struct Progress: Sendable {
        public let stage: ScanStage
        public let filesScanned: Int
        public let duplicateGroupsFound: Int

        public init(stage: ScanStage, filesScanned: Int, duplicateGroupsFound: Int) {
            self.stage = stage
            self.filesScanned = filesScanned
            self.duplicateGroupsFound = duplicateGroupsFound
        }
    }

    private let fm = FileManager.default
    private let safetyManager: SafetyManager

    /// System and user directory names to skip during duplicate scanning — system OS directories, Library, VCS, caches, package managers, asset catalogs.
    private static let excludedDirectoryNames: Set<String> = [
        // System OS roots
        "System", "Library", "Applications", "usr", "bin", "sbin",
        "private", "etc", "var", "tmp", "opt", "dev", "Volumes",
        "Network", "cores",
        // Developer & Build artifacts
        "DerivedData", ".build", "build", "Build", "bin", "obj", "out",
        ".git", ".svn", ".hg",
        "node_modules", ".npm", "Pods", ".cocoapods",
        "__pycache__", ".tox", "venv", ".venv",
        ".Trash", ".Spotlight-V100", ".fseventsd",
        "Intermediates.noindex", "Index.noindex",
        ".swiftpm", "Assets.xcassets", "xcassets",
        ".config", ".cache", ".local", ".vscode", ".idea", ".eclipse",
        ".m2", ".cargo", ".rustup", ".gradle", ".nvm", ".yarn",
        ".docker", ".kube", ".aws", ".ssh", ".gnupg"
    ]

    /// Directory extensions whose contents must NEVER be scanned as user duplicates (Asset catalogs, Xcode projects, App bundles).
    private static let excludedDirectoryExtensions: Set<String> = [
        "xcassets", "imageset", "appiconset", "colorset", "symbolset", "dataset", "stitchgroup",
        "xcodeproj", "xcworkspace", "xcdatamodeld",
        "app", "framework", "plugin", "bundle", "kext", "systemextension", "qlgenerator", "mdimporter", "dsym"
    ]

    /// File extensions to skip — source code, build intermediates, system resources, and database files that must never be deleted as user duplicates.
    private static let excludedExtensions: Set<String> = [
        // Build & Intermediate files
        "o", "d", "dia", "swiftdeps", "swiftsourceinfo",
        "swiftmodule", "swiftinterface", "swiftdoc",
        "hmap", "modulemap", "pcm", "pch",
        "pyc", "pyo", "class", "a", "dylib", "so",
        // Source Code & Project Configs
        "swift", "m", "h", "mm", "c", "cpp", "hpp", "cs", "java", "kt",
        "ts", "js", "jsx", "tsx", "py", "rb", "go", "rs", "php",
        "css", "scss", "sass", "less", "html", "htm", "xml", "json", "yaml", "yml",
        "plist", "storyboard", "xib", "entitlements", "pbxproj", "lock", "toml",
        "properties", "gradle", "cmake", "make",
        // System Resources, Fonts, Localizations & Databases
        "strings", "stringsdict", "po", "mo", "icns", "car", "nib",
        "ttf", "otf", "woff", "woff2", "eot", "icc", "icm", "xmp",
        "dat", "icu", "db", "sqlite", "sqlite3", "db-wal", "db-shm", "log"
    ]

    public init(safetyManager: SafetyManager = SafetyManager()) {
        self.safetyManager = safetyManager
    }

    /// Checks if a file path is safe to scan and recommend for user duplicate removal.
    private func isSafeUserFilePath(_ path: String) -> Bool {
        // User temp (`/var/folders/…`, `/private/var/folders/…`) is a valid scan root.
        if path.hasPrefix("/var/folders/") || path.hasPrefix("/private/var/folders/") {
            return true
        }

        let forbiddenPrefixes = [
            "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
            "/private", "/etc", "/var", "/tmp", "/opt", "/dev", "/Volumes", "/Network", "/cores"
        ]
        for prefix in forbiddenPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return false
            }
        }

        let home = fm.homeDirectoryForCurrentUser.path
        let userForbiddenPrefixes = [
            "\(home)/Library",
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/.Trash"
        ]
        for prefix in userForbiddenPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return false
            }
        }

        return true
    }

    /// Scans a directory for duplicate files using multi-stage comparison (Size -> Header SHA256 -> Full SHA256).
    public func scan(
        directory: URL,
        minSizeBytes: Int64 = 51200, // 50 KB minimum
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> [DuplicateGroup] {
        try Task.checkCancellation()

        progress?(Progress(stage: .collectingFiles, filesScanned: 0, duplicateGroupsFound: 0))

        var filesBySize: [Int64: [URL]] = [:]
        var totalScanned = 0

        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey
        ]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        while let obj = enumerator.nextObject() {
            try Task.checkCancellation()
            guard let fileURL = obj as? URL else { continue }

            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }

            let path = fileURL.path
            let dirName = fileURL.lastPathComponent
            let dirExt = fileURL.pathExtension.lowercased()

            // Skip system & excluded directories immediately
            if resourceValues.isDirectory == true {
                if Self.excludedDirectoryNames.contains(dirName) || Self.excludedDirectoryExtensions.contains(dirExt) || !isSafeUserFilePath(path) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if resourceValues.isSymbolicLink == true || resourceValues.isPackage == true {
                continue
            }

            // Enforce system path safety check
            guard isSafeUserFilePath(path) else { continue }

            // Skip excluded file extensions
            let pathExt = fileURL.pathExtension.lowercased()
            if Self.excludedExtensions.contains(pathExt) { continue }

            // Double-check path components for asset containers or project bundles
            let pathComponents = fileURL.pathComponents
            if pathComponents.contains(where: { comp in
                let ext = (comp as NSString).pathExtension.lowercased()
                return Self.excludedDirectoryNames.contains(comp) || Self.excludedDirectoryExtensions.contains(ext)
            }) {
                continue
            }

            let size = Int64(resourceValues.fileSize ?? 0)
            guard size >= minSizeBytes else { continue }

            totalScanned += 1
            filesBySize[size, default: []].append(fileURL)

            if totalScanned % 500 == 0 {
                progress?(Progress(stage: .collectingFiles, filesScanned: totalScanned, duplicateGroupsFound: 0))
            }
        }

        // Stage 1: Keep sizes with >= 2 files
        progress?(Progress(stage: .sizeFiltering, filesScanned: totalScanned, duplicateGroupsFound: 0))
        let sizeCandidates = filesBySize.filter { $0.value.count > 1 }

        var headerCandidates: [String: [URL]] = [:]
        var totalHeaderCheck = 0
        for urls in sizeCandidates.values {
            totalHeaderCheck += urls.count
        }

        // Stage 2: Header 4KB Hash
        var currentHeaderCheck = 0
        for (size, urls) in sizeCandidates {
            try Task.checkCancellation()
            for url in urls {
                try Task.checkCancellation()
                currentHeaderCheck += 1
                progress?(Progress(
                    stage: .headerHashing(current: currentHeaderCheck, total: totalHeaderCheck),
                    filesScanned: totalScanned,
                    duplicateGroupsFound: 0
                ))

                if let headerHash = computeHeaderHash(fileURL: url) {
                    let key = "\(size)_\(headerHash)"
                    headerCandidates[key, default: []].append(url)
                }
            }
        }

        let fullCandidates = headerCandidates.filter { $0.value.count > 1 }
        var totalFullCheck = 0
        for urls in fullCandidates.values {
            totalFullCheck += urls.count
        }

        // Stage 3: Full SHA-256 Hash
        var fullHashGroups: [String: [(url: URL, date: Date?)]] = [:]
        var currentFullCheck = 0
        let foundGroupsCount = 0

        for urls in fullCandidates.values {
            try Task.checkCancellation()
            for url in urls {
                try Task.checkCancellation()
                currentFullCheck += 1

                if let fullHash = computeFullHash(fileURL: url) {
                    let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    fullHashGroups[fullHash, default: []].append((url: url, date: modDate))
                }

                progress?(Progress(
                    stage: .fullHashing(current: currentFullCheck, total: totalFullCheck),
                    filesScanned: totalScanned,
                    duplicateGroupsFound: foundGroupsCount
                ))
            }
        }

        var resultGroups: [DuplicateGroup] = []

        for (hash, items) in fullHashGroups where items.count > 1 {
            let fileSize = (try? items.first?.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

            let duplicateItems = items.map { item in
                DuplicateFileItem(
                    url: item.url,
                    sizeBytes: Int64(fileSize),
                    modificationDate: item.date,
                    isSelected: false
                )
            }

            let group = DuplicateGroup(
                fileSize: Int64(fileSize),
                hashValue: hash,
                items: duplicateItems
            )
            resultGroups.append(group)
        }

        // Sort groups by size descending
        resultGroups.sort { $0.fileSize > $1.fileSize }

        // Default smart selection: Keep Oldest
        resultGroups = applySmartSelect(groups: resultGroups, strategy: .keepOldest)

        progress?(Progress(
            stage: .completed,
            filesScanned: totalScanned,
            duplicateGroupsFound: resultGroups.count
        ))

        return resultGroups
    }

    /// Computes 4KB header SHA-256 hash.
    private func computeHeaderHash(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 4096) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Computes full SHA-256 hash via streaming chunks.
    private func computeFullHash(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 64 * 1024 // 64KB

        while true {
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Applies smart selection strategy to duplicate groups.
    public func applySmartSelect(groups: [DuplicateGroup], strategy: SmartSelectStrategy) -> [DuplicateGroup] {
        return groups.map { group in
            var updatedGroup = group
            let items = group.items

            switch strategy {
            case .keepOldest:
                // Sort by modification date ascending (oldest first). Keep 1st, select others.
                let sortedIndices = items.indices.sorted { idx1, idx2 in
                    let d1 = items[idx1].modificationDate ?? Date.distantFuture
                    let d2 = items[idx2].modificationDate ?? Date.distantFuture
                    return d1 < d2
                }
                for (position, index) in sortedIndices.enumerated() {
                    updatedGroup.items[index].isSelected = (position != 0)
                }

            case .keepNewest:
                // Sort by modification date descending (newest first). Keep 1st, select others.
                let sortedIndices = items.indices.sorted { idx1, idx2 in
                    let d1 = items[idx1].modificationDate ?? Date.distantPast
                    let d2 = items[idx2].modificationDate ?? Date.distantPast
                    return d1 > d2
                }
                for (position, index) in sortedIndices.enumerated() {
                    updatedGroup.items[index].isSelected = (position != 0)
                }

            case .selectAll:
                for idx in updatedGroup.items.indices {
                    updatedGroup.items[idx].isSelected = true
                }

            case .deselectAll:
                for idx in updatedGroup.items.indices {
                    updatedGroup.items[idx].isSelected = false
                }
            }

            return updatedGroup
        }
    }

    /// Trashes selected files using macOS trashItem.
    public func trashSelectedFiles(
        groups: [DuplicateGroup],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> (removedCount: Int, freedBytes: Int64) {
        var removedCount = 0
        var freedBytes: Int64 = 0

        let selectedItems = groups.flatMap { $0.items.filter(\.isSelected) }
        let total = selectedItems.count

        for (index, item) in selectedItems.enumerated() {
            try Task.checkCancellation()
            progress?(index + 1, total)

            let url = item.url
            guard isSafeUserFilePath(url.path) else {
                Logger.duplicateEngine.warning("Refused to trash unsafe path: \(url.path, privacy: .public)")
                continue
            }
            if fm.fileExists(atPath: url.path) {
                do {
                    var trashedURL: NSURL?
                    try fm.trashItem(at: url, resultingItemURL: &trashedURL)
                    removedCount += 1
                    freedBytes += item.sizeBytes
                    Logger.duplicateEngine.info("Trashed duplicate file: \(url.path, privacy: .public)")
                } catch {
                    Logger.duplicateEngine.error("Failed to trash duplicate file \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        return (removedCount, freedBytes)
    }
}
