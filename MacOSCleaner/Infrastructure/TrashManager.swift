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
    private let bookmarkKey = "com.macoscleaner.trashBookmark"
    
    public init(safetyManager: SafetyManager = SafetyManager(), fileManager: FileManager = .default) {
        self.safetyManager = safetyManager
        self.fileManager = fileManager
    }
    
    @discardableResult
    public func trashItem(at url: URL, policy: DeletionPolicy = .cleanup) throws -> URL {
        try safetyManager.validate(url: url, policy: policy)
        
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
    
    /// Wholesale `~/.Trash` empty is disabled — would delete unrelated user items.
    /// Use `permanentlyDelete(urls:)` with session-selected / just-trashed URLs only.
    @discardableResult
    public func emptyTrash() async throws -> Int64 {
        Logger.trash.error("emptyTrash() refused — wholesale Trash wipe disabled")
        throw TrashError.trashOperationFailed(
            "Wholesale emptyTrash is disabled; permanently delete only explicitly selected URLs."
        )
    }

    /// Permanently deletes only the given URLs (typically items just moved into Trash).
    /// Does not empty unrelated Trash contents.
    @discardableResult
    public func permanentlyDelete(urls: [URL]) async throws -> Int64 {
        try await ensureAccess()

        var totalFreed: Int64 = 0
        var failedCount = 0

        for url in urls {
            do {
                try Task.checkCancellation()
                try safetyManager.validate(url: url)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                let size = fileManager.getDirectorySize(url: url)
                try fileManager.removeItem(at: url)
                totalFreed += size
                Logger.trash.debug("Permanently deleted: \(url.path, privacy: .public) (\(size) bytes)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedCount += 1
                Logger.trash.error("Failed to delete '\(url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        if failedCount > 0 {
            Logger.trash.warning("permanentlyDelete: \(urls.count) items, \(failedCount) failures, \(totalFreed) bytes freed")
        } else {
            Logger.trash.info("permanentlyDelete: \(urls.count) items deleted, \(totalFreed) bytes freed")
        }

        return totalFreed
    }
    
    nonisolated public func ensureAccess() async throws {
        let fileManager = FileManager.default
        let trashURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        
        if hasAccess() { return }
        if loadBookmark() { return }
        
        Logger.trash.info("No Trash access — requesting via NSOpenPanel")
        
        try await MainActor.run {
            let panel = NSOpenPanel()
            panel.message = "trash_access_prompt_message".localized
            panel.prompt = "trash_access_prompt_button".localized
            panel.directoryURL = trashURL
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.showsHiddenFiles = true
            panel.allowsMultipleSelection = false
            
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                self.saveBookmark(for: url)
            } else if response != .OK {
                Logger.trash.error("User denied Trash access via NSOpenPanel")
                throw TrashError.trashOperationFailed("Permission to access Trash was denied.")
            }
        }
        
        let granted = hasAccess()
        if !granted {
            Logger.trash.error("Trash access still not available after NSOpenPanel confirmation")
            throw TrashError.trashOperationFailed("Permission to access Trash was not granted.")
        }
        Logger.trash.info("Trash access granted")
    }
    
    nonisolated public func requestTrashAccess() async throws {
        try await ensureAccess()
    }
    
    nonisolated private func hasAccess() -> Bool {
        let fileManager = FileManager.default
        let trashURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        return (try? fileManager.contentsOfDirectory(atPath: trashURL.path)) != nil
    }
    
    nonisolated private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            let _ = url.startAccessingSecurityScopedResource()
            Logger.trash.info("Saved security-scoped bookmark for Trash")
        } catch {
            Logger.trash.error("Failed to save bookmark: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    nonisolated private func loadBookmark() -> Bool {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return false
        }
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                Logger.trash.warning("Stale bookmark detected, will re-request access")
                return false
            }
            
            let _ = url.startAccessingSecurityScopedResource()
            Logger.trash.info("Successfully loaded security-scoped bookmark for Trash")
            return true
        } catch {
            Logger.trash.error("Failed to load bookmark: \(error.localizedDescription, privacy: .public)")
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return false
        }
    }
}
