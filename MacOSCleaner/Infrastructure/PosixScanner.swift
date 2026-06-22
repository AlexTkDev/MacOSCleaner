import Foundation
import OSLog

private let scannerLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "PosixScanner")

public struct PosixScanner: Sendable {
    public struct Config: Sendable {
        public let excludedPrefixes: [String]
        public let maxDepth: Int?
        public let batchSize: Int
        public let yieldInterval: Duration

        public init(
            excludedPrefixes: [String] = ["/Library/", "/.Trash/", "/.git/"],
            maxDepth: Int? = nil,
            batchSize: Int = 1000,
            yieldInterval: Duration = .seconds(2)
        ) {
            self.excludedPrefixes = excludedPrefixes
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
        return AsyncStream { continuation in
            let task = Task {
                let fm = FileManager.default
                let allRoots = safeRoots.filter { fm.fileExists(atPath: $0) }
                var totalScanned = 0
                var totalFound = 0

                await withTaskGroup(of: (Int, Int, [Entry]).self) { group in
                    for root in allRoots {
                        group.addTask {
                            var scanned = 0
                            var found = 0
                            var entries: [Entry] = []
                            var visitedInodes = Set<UInt64>()

                            Self.scanRecursive(
                                root,
                                depth: 0,
                                config: safeConfig,
                                visitedInodes: &visitedInodes,
                                scanned: &scanned,
                                found: &found,
                                entries: &entries
                            )

                            return (scanned, found, entries)
                        }
                    }

                    for await (scanned, found, entries) in group {
                        totalScanned += scanned
                        totalFound += found
                        if !entries.isEmpty {
                            continuation.yield(entries)
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

    private static func scanRecursive(
        _ path: String,
        depth: Int,
        config: Config,
        visitedInodes: inout Set<UInt64>,
        scanned: inout Int,
        found: inout Int,
        entries: inout [Entry]
    ) {
        if let maxDepth = config.maxDepth, depth > maxDepth { return }

        guard let dir = opendir(path) else {
            scannerLog.warning("opendir failed: \(path) — \(String(cString: strerror(errno)))")
            return
        }
        defer { closedir(dir) }

        var dirStat = Darwin.stat()
        if fstat(Darwin.dirfd(dir), &dirStat) == 0 {
            let inode = dirStat.st_ino
            if visitedInodes.contains(inode) {
                scannerLog.warning("Symlink loop detected, skipping: \(path) (inode: \(inode))")
                return
            }
            visitedInodes.insert(inode)
        }

        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." { continue }

            let fullPath = "\(path)/\(name)"
            let isDir = entry.pointee.d_type == DT_DIR
            let isLink = entry.pointee.d_type == DT_LNK
            let inode = entry.pointee.d_ino

            scanned += 1

            var excluded = false
            for prefix in config.excludedPrefixes {
                if fullPath.contains(prefix) {
                    excluded = true
                    break
                }
            }

            if !excluded {
                entries.append(Entry(
                    path: fullPath,
                    name: name,
                    isDirectory: isDir,
                    isSymlink: isLink,
                    depth: depth,
                    inode: inode
                ))
                found += 1
            }

            if isDir {
                scanRecursive(
                    fullPath,
                    depth: depth + 1,
                    config: config,
                    visitedInodes: &visitedInodes,
                    scanned: &scanned,
                    found: &found,
                    entries: &entries
                )
            }
        }
    }
}
