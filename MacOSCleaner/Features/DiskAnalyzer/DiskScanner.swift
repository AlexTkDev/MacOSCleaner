import Foundation
import OSLog

public actor DiskScanner {
    private let logger = Logger(subsystem: "input.MacOSCleaner", category: "DiskScanner")
    
    public init() {}
    
    /// Scans a directory and returns its immediate children with calculated sizes.
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
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        
        // 1. Get immediate children
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        let childrenURLs = try fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        
        var results: [DiskItem] = []
        var dirsToScan: [URL] = []
        
        for url in childrenURLs {
            if Task.isCancelled { break }
            
            // Check exclusion
            if FileManager.shouldExclude(url: url) {
                continue
            }
            
            guard let resourceValues = try? url.resourceValues(forKeys: Set(keys)) else {
                continue
            }
            
            let isDirectory = resourceValues.isDirectory ?? false
            if isDirectory {
                // If it's a bundle like .app, we treat it as a file/app category
                if url.pathExtension.lowercased() == "app" {
                    let size = await calculateDirectorySize(url: url)
                    results.append(DiskItem(
                        url: url,
                        name: url.lastPathComponent,
                        isDirectory: false,
                        size: size,
                        fileType: .apps
                    ))
                } else {
                    dirsToScan.append(url)
                }
            } else {
                let size = Int64(resourceValues.fileSize ?? 0)
                results.append(DiskItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: false,
                    size: size,
                    fileType: FileCategory.from(url: url)
                ))
            }
        }
        
        if Task.isCancelled { return results }
        
        // 2. Scan directories in parallel using TaskGroup
        let scannedDirs = try await withThrowingTaskGroup(of: DiskItem?.self) { group in
            for dirURL in dirsToScan {
                group.addTask {
                    if Task.isCancelled { return nil }
                    let name = dirURL.lastPathComponent
                    onProgress(name)
                    
                    let size = await self.calculateDirectorySize(url: dirURL)
                    
                    // Also recursively scan 1 level deeper to show children inside if expanded
                    let children = await self.scanSubdirectoryOneLevel(url: dirURL)
                    
                    return DiskItem(
                        url: dirURL,
                        name: name,
                        isDirectory: true,
                        size: size,
                        children: children,
                        fileType: .other
                    )
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
        
        results.append(contentsOf: scannedDirs)
        
        // Sort by size descending
        return results.sorted { $0.size > $1.size }
    }
    
    private func scanSubdirectoryOneLevel(url: URL) async -> [DiskItem] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let childrenURLs = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        var list: [DiskItem] = []
        for child in childrenURLs {
            if Task.isCancelled { break }
            if FileManager.shouldExclude(url: child) { continue }
            
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = values.isDirectory ?? false
            
            if isDir {
                if child.pathExtension.lowercased() == "app" {
                    let size = await calculateDirectorySize(url: child)
                    list.append(DiskItem(
                        url: child,
                        name: child.lastPathComponent,
                        isDirectory: false,
                        size: size,
                        fileType: .apps
                    ))
                } else {
                    let size = await calculateDirectorySize(url: child)
                    list.append(DiskItem(
                        url: child,
                        name: child.lastPathComponent,
                        isDirectory: true,
                        size: size,
                        fileType: .other
                    ))
                }
            } else {
                let size = Int64(values.fileSize ?? 0)
                list.append(DiskItem(
                    url: child,
                    name: child.lastPathComponent,
                    isDirectory: false,
                    size: size,
                    fileType: FileCategory.from(url: child)
                ))
            }
        }
        
        return list.sorted { $0.size > $1.size }
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
            
            if FileManager.shouldExclude(url: fileURL) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = values.isDirectory ?? false
            
            if !isDir {
                totalSize += Int64(values.fileSize ?? 0)
            }
            
            count += 1
            if count % 500 == 0 {
                await Task.yield()
            }
        }
        
        return totalSize
    }
}
