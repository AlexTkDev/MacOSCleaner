import Foundation

public enum TrashError: Error, Equatable {
    case trashOperationFailed(String)
}

public actor TrashManager {
    private let safetyManager: SafetyManager
    private let fileManager: FileManager
    
    public init(safetyManager: SafetyManager = SafetyManager(), fileManager: FileManager = .default) {
        self.safetyManager = safetyManager
        self.fileManager = fileManager
    }
    
    /// Trashes the item at the specified URL after validating it with SafetyManager.
    /// - Parameter url: The URL of the file or directory to trash.
    /// - Returns: The URL of the item in the Trash, which can be used for restore operations.
    @discardableResult
    public func trashItem(at url: URL) throws -> URL {
        try safetyManager.validate(url: url)
        
        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            guard let result = resultingURL as URL? else {
                throw TrashError.trashOperationFailed("Could not determine resulting URL in Trash.")
            }
            return result
        } catch {
            throw TrashError.trashOperationFailed(error.localizedDescription)
        }
    }
    
    /// Empties the user's Recycle Bin (~/.Trash) by deleting all its contents.
    /// Returns the number of bytes freed.
    @discardableResult
    public func emptyTrash() async throws -> Int64 {
        let trashURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard fileManager.fileExists(atPath: trashURL.path) else { return 0 }
        
        var totalFreed: Int64 = 0
        let contents = try fileManager.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: [.fileSizeKey], options: [])
        
        for url in contents {
            do {
                try safetyManager.validate(url: url)
                let size = fileManager.getDirectorySize(url: url)
                try fileManager.removeItem(at: url)
                totalFreed += size
            } catch {
                continue
            }
        }
        return totalFreed
    }
}
