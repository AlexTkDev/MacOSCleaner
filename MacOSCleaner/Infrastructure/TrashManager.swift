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
    nonisolated public let trashDirectoryURL: URL
    
    public init(
        safetyManager: SafetyManager = SafetyManager(),
        fileManager: FileManager = .default,
        trashDirectoryURL: URL? = nil
    ) {
        self.safetyManager = safetyManager
        self.fileManager = fileManager
        self.trashDirectoryURL = trashDirectoryURL ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }
    
    @discardableResult
    public func trashItem(at url: URL, policy: DeletionPolicy = .cleanup) async throws -> URL {
        let results = try await trashItems(urls: [url], policy: policy)
        guard let first = results.first else {
            throw TrashError.trashOperationFailed("No item trashed")
        }
        return first
    }

    /// Moves a single item to Trash or permanently deletes it when `bypassTrash` is true.
    public func removeItem(at url: URL, bypassTrash: Bool, policy: DeletionPolicy = .cleanup) async throws {
        try safetyManager.validate(url: url, policy: policy)
        guard fileManager.fileExists(atPath: url.path) else { return }
        if bypassTrash {
            try fileManager.removeItem(at: url)
        } else {
            try await trashItem(at: url, policy: policy)
        }
    }

    /// Trashes multiple items using standard user-level FileManager APIs (no privileged elevation).
    @discardableResult
    public func trashItems(urls: [URL], policy: DeletionPolicy = .cleanup) async throws -> [URL] {
        guard !urls.isEmpty else { return [] }

        for url in urls {
            try safetyManager.validate(url: url, policy: policy)
        }

        var trashedURLs: [URL] = []
        var failedURLs: [URL] = []
        var missingURLs: [URL] = []

        // If an isolated test trash directory is configured (different from system ~/.Trash), simulate trash by moving into trashDirectoryURL
        let systemTrashDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").standardizedFileURL
        let isIsolatedTestTrash = trashDirectoryURL.standardizedFileURL != systemTrashDir

        if isIsolatedTestTrash {
            for url in urls {
                guard fileManager.fileExists(atPath: url.path) else {
                    missingURLs.append(url)
                    continue
                }
                let targetURL = uniqueDestination(for: url, in: trashDirectoryURL)
                do {
                    try fileManager.moveItem(at: url, to: targetURL)
                    trashedURLs.append(targetURL)
                } catch {
                    failedURLs.append(url)
                }
            }
            if trashedURLs.isEmpty, !missingURLs.isEmpty {
                throw TrashError.trashOperationFailed("Item does not exist")
            }
            if trashedURLs.isEmpty, !failedURLs.isEmpty {
                throw TrashError.trashOperationFailed("Failed to move \(failedURLs.count) item(s) to Trash")
            }
            return trashedURLs
        }

        // Try standard FileManager.trashItem on MainActor for all items (0 prompts for user files)
        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else {
                missingURLs.append(url)
                Logger.trash.debug("Trash skipped missing item: \(url.path, privacy: .public)")
                continue
            }

            var resultingURL: NSURL?
            var success = false
            do {
                try await MainActor.run {
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                }
                if let result = resultingURL as URL? {
                    trashedURLs.append(result)
                    success = true
                    Logger.trash.debug("Trashed item via FileManager: \(url.path, privacy: .public)")
                }
            } catch {
                Logger.trash.debug("FileManager.trashItem failed for '\(url.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }

            if !success {
                failedURLs.append(url)
            }
        }

        if trashedURLs.isEmpty, !failedURLs.isEmpty {
            throw TrashError.trashOperationFailed("Failed to move \(failedURLs.count) item(s) to Trash")
        }
        if trashedURLs.isEmpty, !missingURLs.isEmpty {
            throw TrashError.trashOperationFailed("Item does not exist")
        }
        if !failedURLs.isEmpty {
            Logger.trash.warning("Trash skipped \(failedURLs.count) item(s) due to insufficient permissions")
        }

        return trashedURLs
    }

    /// Permanently deletes only the given URLs (typically items just moved into Trash, or contents of ~/.Trash).
    @discardableResult
    public func permanentlyDelete(urls: [URL]) async throws -> Int64 {
        try await ensureAccess()

        var totalFreed: Int64 = 0

        let systemTrashURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").standardizedFileURL
        let customTrashURL = trashDirectoryURL.standardizedFileURL

        for url in urls {
            do {
                try Task.checkCancellation()
                let stdURL = url.standardizedFileURL
                guard stdURL != customTrashURL && stdURL != systemTrashURL else {
                    Logger.trash.warning("Refusing to delete ~/.Trash directory itself")
                    continue
                }
                guard isDirectTrashChild(stdURL) else {
                    Logger.trash.warning("Refusing permanent delete outside Trash: \(stdURL.path, privacy: .public)")
                    continue
                }
                guard fileManager.fileExists(atPath: stdURL.path) else { continue }
                let size = fileManager.getPhysicalDirectorySize(url: stdURL)
                try fileManager.removeItem(at: stdURL)
                totalFreed += size
                Logger.trash.debug("Permanently deleted: \(stdURL.path, privacy: .public) (\(size) bytes)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.trash.error("Failed to delete '\(url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        return totalFreed
    }
    
    private func uniqueDestination(for source: URL, in trash: URL) -> URL {
        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        var index = 0
        while true {
            let name: String
            if index == 0 {
                name = source.lastPathComponent
            } else if ext.isEmpty {
                name = "\(base) \(index)"
            } else {
                name = "\(base) \(index).\(ext)"
            }
            let candidate = trash.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func isDirectTrashChild(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        if parent == trashDirectoryURL.standardizedFileURL.path { return true }
        let homeTrash = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
            .standardizedFileURL.path
        if parent == homeTrash { return true }
        let uid = String(getuid())
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 6, parts.dropFirst().first == "Volumes" else { return false }
        return parts[parts.count - 3] == ".Trashes" && parts[parts.count - 2] == uid
    }

    nonisolated public func ensureAccess() async throws {
        let trashURL = trashDirectoryURL
        
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
        let trashURL = trashDirectoryURL
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
