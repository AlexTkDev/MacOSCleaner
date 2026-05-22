import Foundation

extension FileManager {
    public func getDirectorySize(url: URL) -> Int64 {
        var size: Int64 = 0
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [])
        while let fileURL = enumerator?.nextObject() as? URL {
            // Skip OrbStack sparse files to avoid massive false positive sizes
            if fileURL.path.contains(".dev.orbstack") {
                continue
            }
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            size += Int64(resourceValues?.fileSize ?? 0)
        }
        return size
    }
}
