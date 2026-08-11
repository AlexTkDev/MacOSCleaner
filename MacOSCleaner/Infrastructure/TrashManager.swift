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
    public func trashItem(at url: URL, policy: DeletionPolicy = .cleanup) async throws -> URL {
        let results = try await trashItems(urls: [url], policy: policy)
        guard let first = results.first else {
            throw TrashError.trashOperationFailed("No item trashed")
        }
        return first
    }

    /// Trashes multiple items efficiently, batching any privileged operations so the user
    /// is prompted for authentication at most ONCE for the entire operation.
    @discardableResult
    public func trashItems(urls: [URL], policy: DeletionPolicy = .cleanup) async throws -> [URL] {
        guard !urls.isEmpty else { return [] }

        for url in urls {
            try safetyManager.validate(url: url, policy: policy)
        }

        var trashedURLs: [URL] = []
        var failedURLs: [URL] = []
        var missingURLs: [URL] = []

        // 1. Try standard FileManager.trashItem on MainActor for all items (0 prompts for user files)
        for url in urls {
            // Missing paths must not fall through to runAsAdmin — AppleScript auth dialog hangs headless CI.
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

        guard !failedURLs.isEmpty else {
            if trashedURLs.isEmpty, !missingURLs.isEmpty {
                throw TrashError.trashOperationFailed("Item does not exist")
            }
            return trashedURLs
        }

        // 2. For items that need elevated permissions, batch them into a single privileged command (1 prompt max)
        let trashDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let trashRoot = trashDir.path
        let escapedTrashRoot = "'\(trashRoot.replacingOccurrences(of: "'", with: "'\\''"))'"
        let uid = getuid()
        let gid = getgid()

        var commands: [String] = []
        var batchTargetURLs: [URL] = []

        for url in failedURLs {
            let escapedSource = "'\(url.path.replacingOccurrences(of: "'", with: "'\\''"))'"
            let targetURL = trashDir.appendingPathComponent(url.lastPathComponent)
            let targetPath = targetURL.path
            let escapedTarget = "'\(targetPath.replacingOccurrences(of: "'", with: "'\\''"))'"

            commands.append("/bin/mv \(escapedSource) \(escapedTrashRoot)/ && /usr/sbin/chown -R \(uid):\(gid) \(escapedTarget)")
            batchTargetURLs.append(targetURL)
        }

        let singleBatchCmd = commands.joined(separator: " && ")
        do {
            _ = try await PrivilegedTaskRunner.runAsAdmin(command: singleBatchCmd)
            trashedURLs.append(contentsOf: batchTargetURLs)
            Logger.trash.info("Trashed \(failedURLs.count) privileged item(s) in a single batch")
        } catch {
            Logger.trash.error("Batch privileged trash failed: \(error.localizedDescription, privacy: .public)")
            throw TrashError.trashOperationFailed(error.localizedDescription)
        }

        return trashedURLs
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
    /// Batches any privileged items so authentication is requested at most ONCE.
    @discardableResult
    public func permanentlyDelete(urls: [URL]) async throws -> Int64 {
        try await ensureAccess()

        var totalFreed: Int64 = 0
        var failedURLs: [URL] = []

        for url in urls {
            do {
                try Task.checkCancellation()
                guard fileManager.fileExists(atPath: url.path) else { continue }
                let size = fileManager.getDirectorySize(url: url)
                do {
                    try fileManager.removeItem(at: url)
                    totalFreed += size
                    Logger.trash.debug("Permanently deleted: \(url.path, privacy: .public) (\(size) bytes)")
                } catch {
                    if (error as NSError).code == NSFileWriteNoPermissionError || (error as NSError).code == Int(EPERM) || (error as NSError).code == Int(EACCES) {
                        failedURLs.append(url)
                    } else {
                        throw error
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.trash.error("Failed to delete '\(url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        if !failedURLs.isEmpty {
            let escaped = failedURLs.map { "'\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")
            do {
                _ = try await PrivilegedTaskRunner.runAsAdmin(command: "/bin/rm -rf \(escaped)")
                for url in failedURLs {
                    let size = fileManager.getDirectorySize(url: url)
                    totalFreed += size
                }
                Logger.trash.info("Permanently deleted \(failedURLs.count) privileged item(s) in a single batch")
            } catch {
                Logger.trash.error("Batch privileged delete failed: \(error.localizedDescription, privacy: .public)")
            }
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
