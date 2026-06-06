import Foundation
import AppKit
import OSLog

private extension Logger {
    static let trash = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "TrashManager")
}

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
            Logger.trash.debug("Trashed item: \(url.path, privacy: .public)")
            return result
        } catch {
            Logger.trash.error("trashItem failed '\(url.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw TrashError.trashOperationFailed(error.localizedDescription)
        }
    }
    
    /// Empties the user's Recycle Bin (~/.Trash) by deleting all its contents.
    /// Logs every failure but always continues — returns total bytes freed.
    @discardableResult
    public func emptyTrash() async throws -> Int64 {
        let trashURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard fileManager.fileExists(atPath: trashURL.path) else {
            Logger.trash.info("Trash folder not found, nothing to empty")
            return 0
        }
        
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: [.fileSizeKey], options: [])
        } catch {
            Logger.trash.error("Cannot list Trash contents: \(error.localizedDescription, privacy: .public)")
            throw TrashError.trashOperationFailed("Cannot list Trash: \(error.localizedDescription)")
        }
        
        var totalFreed: Int64 = 0
        var failedCount = 0
        
        for url in contents {
            do {
                try safetyManager.validate(url: url)
                let size = fileManager.getDirectorySize(url: url)
                try fileManager.removeItem(at: url)
                totalFreed += size
                Logger.trash.debug("Deleted from Trash: \(url.path, privacy: .public) (\(size) bytes)")
            } catch {
                failedCount += 1
                // Log error but continue — never abort mid-loop
                Logger.trash.error("Failed to delete '\(url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        
        if failedCount > 0 {
            Logger.trash.warning("emptyTrash: \(contents.count) items, \(failedCount) failures, \(totalFreed) bytes freed")
        } else {
            Logger.trash.info("emptyTrash: all \(contents.count) items deleted, \(totalFreed) bytes freed")
        }
        
        return totalFreed
    }
    
    nonisolated public func requestTrashAccess() async throws {
        let fileManager = FileManager.default
        let trashURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        
        let hasAccess = (try? fileManager.contentsOfDirectory(atPath: trashURL.path)) != nil
        if hasAccess { return }
        
        Logger.trash.info("No Trash access — requesting via NSOpenPanel")
        
        try await MainActor.run {
            let panel = NSOpenPanel()
            panel.message = NSLocalizedString("Please select the Trash folder to grant access for scanning and cleaning. (It is already selected, just click 'Grant Access')", comment: "")
            panel.prompt = NSLocalizedString("Grant Access", comment: "")
            panel.directoryURL = trashURL
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.showsHiddenFiles = true
            panel.allowsMultipleSelection = false
            
            let response = panel.runModal()
            if response != .OK {
                Logger.trash.error("User denied Trash access via NSOpenPanel")
                throw TrashError.trashOperationFailed("Permission to access Trash was denied.")
            }
        }
        
        let granted = (try? fileManager.contentsOfDirectory(atPath: trashURL.path)) != nil
        if !granted {
            Logger.trash.error("Trash access still not available after NSOpenPanel confirmation")
            throw TrashError.trashOperationFailed("Permission to access Trash was not granted.")
        }
        Logger.trash.info("Trash access granted")
    }
}
