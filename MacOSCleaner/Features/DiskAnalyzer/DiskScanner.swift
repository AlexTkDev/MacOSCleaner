import Foundation
import OSLog

public actor DiskScanner {
    private let logger = Logger(subsystem: "input.MacOSCleaner", category: "DiskScanner")
    
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "photoslibrary",
        "savedstate", "pkg", "dmg", "lproj", "workflow", "qlgenerator", "prefpane"
    ]
    
    public init() {}
    
    /// Scans a directory and returns its hierarchical tree rooted at `directoryURL`.
    public func scan(
        directoryURL: URL,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> DiskItem {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Scanning disk space at \(directoryURL.lastPathComponent)"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }
        
        let rootURL = directoryURL.standardizedFileURL
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        
        let rootNode = DirectoryNode(url: rootURL, name: rootURL.lastPathComponent, parentURL: nil)
        var directoryNodes: [URL: DirectoryNode] = [rootURL: rootNode]
        
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return rootNode.toDiskItem()
        }
        
        var count = 0
        
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            let standardURL = fileURL.standardizedFileURL
            
            if FileManager.shouldExclude(url: standardURL) {
                if (try? standardURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            guard let values = try? standardURL.resourceValues(forKeys: Set(keys)) else { continue }
            
            // Skip dataless iCloud files to avoid triggering network downloads
            if let isUbiquitous = values.isUbiquitousItem, isUbiquitous {
                if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
            }
            
            let isDir = values.isDirectory ?? false
            let ext = standardURL.pathExtension.lowercased()
            let isPackage = (values.isPackage ?? false) || Self.packageExtensions.contains(ext)
            
            if isDir && !isPackage {
                let parentURL = standardURL.deletingLastPathComponent().standardizedFileURL
                let parentNode = getOrCreateDirectoryNode(
                    url: parentURL,
                    rootURL: rootURL,
                    directoryNodes: &directoryNodes
                )
                let node = DirectoryNode(
                    url: standardURL,
                    name: standardURL.lastPathComponent,
                    parentURL: parentURL
                )
                directoryNodes[standardURL] = node
                parentNode.subdirectories[standardURL] = node
            } else if isDir && isPackage {
                enumerator.skipDescendants()
                let pkgSize = await calculatePackageSize(url: standardURL)
                let parentURL = standardURL.deletingLastPathComponent().standardizedFileURL
                let parentNode = getOrCreateDirectoryNode(
                    url: parentURL,
                    rootURL: rootURL,
                    directoryNodes: &directoryNodes
                )
                
                let item = DiskItem(
                    url: standardURL,
                    name: standardURL.lastPathComponent,
                    isDirectory: true,
                    isPackage: true,
                    size: pkgSize.size,
                    fileCount: pkgSize.fileCount,
                    fileType: .apps,
                    parentURL: parentURL
                )
                parentNode.fileChildren.append(item)
                propagateSize(pkgSize.size, fileCount: pkgSize.fileCount, from: parentNode, directoryNodes: directoryNodes, rootURL: rootURL)
            } else {
                let allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                let parentURL = standardURL.deletingLastPathComponent().standardizedFileURL
                let parentNode = getOrCreateDirectoryNode(
                    url: parentURL,
                    rootURL: rootURL,
                    directoryNodes: &directoryNodes
                )
                
                let item = DiskItem(
                    url: standardURL,
                    name: standardURL.lastPathComponent,
                    isDirectory: false,
                    isPackage: false,
                    size: allocatedSize,
                    fileCount: 1,
                    fileType: FileCategory.from(url: standardURL),
                    parentURL: parentURL
                )
                parentNode.fileChildren.append(item)
                propagateSize(allocatedSize, fileCount: 1, from: parentNode, directoryNodes: directoryNodes, rootURL: rootURL)
            }
            
            count += 1
            if count % 1000 == 0 {
                onProgress(standardURL.lastPathComponent)
                await Task.yield()
            }
        }
        
        return rootNode.toDiskItem()
    }
    
    private func getOrCreateDirectoryNode(
        url: URL,
        rootURL: URL,
        directoryNodes: inout [URL: DirectoryNode]
    ) -> DirectoryNode {
        if let existing = directoryNodes[url] {
            return existing
        }
        
        let parentURL = url.deletingLastPathComponent().standardizedFileURL
        let parentNode: DirectoryNode?
        if url != rootURL && url.path.hasPrefix(rootURL.path) {
            parentNode = getOrCreateDirectoryNode(
                url: parentURL,
                rootURL: rootURL,
                directoryNodes: &directoryNodes
            )
        } else {
            parentNode = nil
        }
        
        let node = DirectoryNode(
            url: url,
            name: url.lastPathComponent,
            parentURL: parentNode?.url
        )
        directoryNodes[url] = node
        parentNode?.subdirectories[url] = node
        return node
    }
    
    private func propagateSize(
        _ size: Int64,
        fileCount: Int,
        from node: DirectoryNode,
        directoryNodes: [URL: DirectoryNode],
        rootURL: URL
    ) {
        var current: DirectoryNode? = node
        while let curr = current {
            curr.size += size
            curr.fileCount += fileCount
            if curr.url == rootURL { break }
            if let pURL = curr.parentURL {
                current = directoryNodes[pURL]
            } else {
                break
            }
        }
    }
    
    private func calculatePackageSize(url: URL) async -> (size: Int64, fileCount: Int) {
        if Task.isCancelled { return (0, 0) }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
        
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let s = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            return (s, 1)
        }
        
        var totalSize: Int64 = 0
        var totalFiles = 0
        
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let isDir = values.isDirectory ?? false
            if !isDir {
                totalSize += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                totalFiles += 1
            }
        }
        
        return (totalSize, max(1, totalFiles))
    }
}

private final class DirectoryNode: @unchecked Sendable {
    let url: URL
    let name: String
    let parentURL: URL?
    var fileCount: Int = 0
    var size: Int64 = 0
    var fileChildren: [DiskItem] = []
    var subdirectories: [URL: DirectoryNode] = [:]
    
    init(url: URL, name: String, parentURL: URL?) {
        self.url = url
        self.name = name
        self.parentURL = parentURL
    }
    
    func toDiskItem() -> DiskItem {
        var allChildren: [DiskItem] = []
        allChildren.append(contentsOf: fileChildren)
        for (_, subNode) in subdirectories {
            allChildren.append(subNode.toDiskItem())
        }
        allChildren.sort { $0.size > $1.size }
        
        return DiskItem(
            url: url,
            name: name.isEmpty ? "/" : name,
            isDirectory: true,
            isPackage: false,
            size: size,
            fileCount: fileCount,
            children: allChildren,
            fileType: .all,
            parentURL: parentURL
        )
    }
}

