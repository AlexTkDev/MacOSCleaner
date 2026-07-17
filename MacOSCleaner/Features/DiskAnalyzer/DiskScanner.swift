import Foundation
import OSLog

public actor DiskScanner {
    private let logger = Logger(subsystem: "input.MacOSCleaner", category: "DiskScanner")
    
    public init() {}
    
    /// Scans a directory and returns its files (flattened) with calculated sizes.
    public func scan(
        directoryURL: URL,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> [DiskItem] {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Scanning disk space at \(directoryURL.lastPathComponent)"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }
        
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                return true // Skip access errors and continue
            }
        ) else {
            return []
        }
        
        var results: [DiskItem] = []
        var appsToCalculate: [URL] = []
        var count = 0
        let minSize: Int64 = 1024 * 1024 // 1 MB
        
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            
            if FileManager.shouldExclude(url: fileURL) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = values.isDirectory ?? false
            
            if isDir {
                if fileURL.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    appsToCalculate.append(fileURL)
                }
            } else {
                let size = Int64(values.fileSize ?? 0)
                if size > minSize {
                    results.append(DiskItem(
                        url: fileURL,
                        name: fileURL.lastPathComponent,
                        isDirectory: false,
                        size: size,
                        fileType: FileCategory.from(url: fileURL)
                    ))
                }
            }
            
            count += 1
            if count % 1000 == 0 {
                onProgress(fileURL.lastPathComponent)
                await Task.yield()
            }
        }
        
        if Task.isCancelled { return results }
        
        // Calculate .app sizes in parallel
        let appItems = try await withThrowingTaskGroup(of: DiskItem?.self) { group in
            for appURL in appsToCalculate {
                group.addTask {
                    if Task.isCancelled { return nil }
                    let size = await self.calculateDirectorySize(url: appURL)
                    if size > minSize {
                        return DiskItem(
                            url: appURL,
                            name: appURL.lastPathComponent,
                            isDirectory: false,
                            size: size,
                            fileType: .apps
                        )
                    }
                    return nil
                }
            }
            
            var list: [DiskItem] = []
            while let item = try await group.next() {
                if let item {
                    list.append(item)
                }
            }
            return list
        }
        
        results.append(contentsOf: appItems)
        
        // Sort by size descending
        return results.sorted { $0.size > $1.size }
    }
    
    private func calculateDirectorySize(url: URL) async -> Int64 {
        if Task.isCancelled { return 0 }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        var count = 0
        
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = values.isDirectory ?? false
            
            if !isDir {
                totalSize += Int64(values.fileSize ?? 0)
            }
            
            count += 1
            if count % 1000 == 0 {
                await Task.yield()
            }
        }
        
        return totalSize
    }
}
