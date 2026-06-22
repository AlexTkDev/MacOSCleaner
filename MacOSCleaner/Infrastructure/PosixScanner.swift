import Foundation
import OSLog

private let scannerLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "PosixScanner")

public struct PosixScanner: Sendable {
    public struct Config: Sendable {
        public let excludedPrefixes: [String]
        public let excludedDirectoryNames: Set<String>
        public let maxDepth: Int?
        public let batchSize: Int
        public let yieldInterval: Duration

        public init(
            excludedPrefixes: [String] = ["/Library/", "/.Trash/", "/.git/"],
            excludedDirectoryNames: Set<String> = [".git", ".Trash", "node_modules", "__MACOSX"],
            maxDepth: Int? = nil,
            batchSize: Int = 1000,
            yieldInterval: Duration = .seconds(1)
        ) {
            self.excludedPrefixes = excludedPrefixes
            self.excludedDirectoryNames = excludedDirectoryNames
            self.maxDepth = maxDepth
            self.batchSize = batchSize
            self.yieldInterval = yieldInterval
        }
    }

    public struct Entry: Sendable {
        public let path: String
        public let name: String
        public let isDirectory: Bool
        public let isSymlink: Bool
        public let depth: Int
        public let inode: UInt64
    }

    public init() {}

    public nonisolated func scanParallel(
        roots: [String],
        config: Config = .init(),
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> AsyncStream<[Entry]> {
        let safeRoots = roots
        let safeConfig = config
        let safeProgress = progress
        return AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation in
            let task = Task {
                let fm = FileManager.default
                let allRoots = safeRoots.filter { fm.fileExists(atPath: $0) }
                let uniqueRoots = Self.deduplicateRoots(allRoots)
                var totalScanned = 0
                var totalFound = 0

                await withTaskGroup(of: (Int, Int, [[Entry]]).self) { group in
                    for root in uniqueRoots {
                        group.addTask {
                            Self.scanRoot(root, config: safeConfig)
                        }
                    }

                    for await (scanned, found, batches) in group {
                        totalScanned += scanned
                        totalFound += found
                        for batch in batches where !batch.isEmpty {
                            continuation.yield(batch)
                        }
                        safeProgress?(totalScanned, totalFound)
                    }
                }

                safeProgress?(totalScanned, totalFound)
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func deduplicateRoots(_ roots: [String]) -> [String] {
        let sorted = roots.sorted { $0.count < $1.count }
        var result: [String] = []
        for root in sorted {
            let isChild = result.contains { root.hasPrefix($0 + "/") }
            if !isChild { result.append(root) }
        }
        return result
    }

    private static func scanRoot(_ root: String, config: Config) -> (Int, Int, [[Entry]]) {
        var allBatches: [[Entry]] = []
        var batch: [Entry] = []
        batch.reserveCapacity(config.batchSize)
        var scanned = 0
        var found = 0
        var visitedInodes = Set<UInt64>()

        var stack: [(path: String, depth: Int)] = [(root, 0)]

        while let (currentPath, depth) = stack.popLast() {
            if Task.isCancelled { break }
            if let maxDepth = config.maxDepth, depth > maxDepth { continue }

            guard let dir = opendir(currentPath) else { continue }

            var dirStat = Darwin.stat()
            if fstat(dirfd(dir), &dirStat) == 0 {
                let inode = dirStat.st_ino
                if visitedInodes.contains(inode) {
                    closedir(dir)
                    continue
                }
                visitedInodes.insert(inode)
            }

            var subdirs: [(String, Int)] = []

            while let entry = readdir(dir) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                if name == "." || name == ".." { continue }
                if config.excludedDirectoryNames.contains(name) { continue }

                let isDir = entry.pointee.d_type == DT_DIR
                let isLink = entry.pointee.d_type == DT_LNK
                let inode = entry.pointee.d_ino
                let fullPath = currentPath + "/" + name

                scanned += 1

                var excluded = false
                for prefix in config.excludedPrefixes {
                    if fullPath.contains(prefix) {
                        excluded = true
                        break
                    }
                }

                if !excluded {
                    batch.append(Entry(
                        path: fullPath,
                        name: name,
                        isDirectory: isDir,
                        isSymlink: isLink,
                        depth: depth,
                        inode: inode
                    ))
                    found += 1

                    if batch.count >= config.batchSize {
                        allBatches.append(batch)
                        batch = []
                        batch.reserveCapacity(config.batchSize)
                    }
                }

                if isDir && !excluded {
                    subdirs.append((fullPath, depth + 1))
                }
            }

            closedir(dir)

            for sub in subdirs.reversed() {
                stack.append(sub)
            }
        }

        if !batch.isEmpty {
            allBatches.append(batch)
        }

        return (scanned, found, allBatches)
    }
}
