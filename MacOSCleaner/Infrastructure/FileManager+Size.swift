import Foundation

extension FileManager {
    /// Paths to exclude from size calculation (sparse files, virtual disks, etc.)
    public static let defaultExcludedPaths: [String] = [
        ".dev.orbstack",
        ".dmg",
        ".sparseimage",
        ".sparsebundle"
    ]
    
    public func getDirectorySize(url: URL, excludedPaths: [String] = FileManager.defaultExcludedPaths) -> Int64 {
        var size: Int64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [])
        while let fileURL = enumerator?.nextObject() as? URL {
            let path = fileURL.path
            let shouldExclude = excludedPaths.contains { path.contains($0) }
            if shouldExclude {
                continue
            }
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            size += Int64(resourceValues?.fileSize ?? 0)
        }
        return size
    }
}
