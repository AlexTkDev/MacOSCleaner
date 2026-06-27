import Foundation
import os.log

/// Cleanup transaction journal for rollback and audit.
/// Uses JSONL (JSON Lines) format for crash-safe writes.
public actor TransactionJournal {
    private let journalURL: URL
    private let archiveDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macoscleaner", category: "TransactionJournal")
    
    /// Maximum journal size before rotation (10MB)
    private let maxJournalSize: Int64 = 10 * 1024 * 1024
    
    public init(journalURL: URL? = nil) {
        if let url = journalURL {
            self.journalURL = url
            self.archiveDirectoryURL = url.deletingLastPathComponent().appendingPathComponent("archives", isDirectory: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let journalDir = appSupport.appendingPathComponent("MacOSCleaner", isDirectory: true)
            try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
            self.journalURL = journalDir.appendingPathComponent("transactions.jsonl")
            self.archiveDirectoryURL = journalDir.appendingPathComponent("archives", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: archiveDirectoryURL, withIntermediateDirectories: true)
    }
    
    /// Writes a new transaction to the journal.
    /// - Parameter transaction: The transaction to write.
    public func log(transaction: CleanupTransaction) throws {
        let data = try encoder.encode(transaction)
        guard var line = String(data: data, encoding: .utf8) else {
            throw JournalError.encodingFailed
        }
        line += "\n"
        
        do {
            try performWrite(line: line)
        } catch {
            logger.error("Failed to write transaction: \(error.localizedDescription)")
            throw JournalError.writeFailed(error)
        }
    }
    
    /// Writes a line to the journal with size check and rotation.
    /// Uses atomic write via full file replacement (read-modify-write).
    private func performWrite(line: String) throws {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
            if let fileSize = attributes[.size] as? Int64, fileSize >= maxJournalSize {
                try rotateJournal()
            }
        }
        
        var existingContent = ""
        if FileManager.default.fileExists(atPath: journalURL.path) {
            existingContent = try String(contentsOf: journalURL, encoding: .utf8)
        }
        
        let newContent = existingContent + line
        let tempURL = journalURL.appendingPathExtension("tmp.\(UUID().uuidString)")
        
        do {
            try newContent.write(to: tempURL, atomically: true, encoding: .utf8)
            
            if FileManager.default.fileExists(atPath: journalURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    journalURL,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.moveItem(at: tempURL, to: journalURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
    
    /// Rotates the journal: archives the current file and creates a new one.
    private func rotateJournal() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let archiveURL = archiveDirectoryURL.appendingPathComponent("transactions_\(timestamp).jsonl")
        
        try FileManager.default.moveItem(at: journalURL, to: archiveURL)
        logger.info("Journal rotated to archive: \(archiveURL.path)")
        
        cleanupOldArchives()
    }
    
    /// Deletes archives older than 30 days, keeping a maximum of 10 archives.
    private func cleanupOldArchives() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: archiveDirectoryURL, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        
        let sortedFiles = files.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return date1 < date2
        }
        
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        for file in sortedFiles {
            if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               creationDate < thirtyDaysAgo || sortedFiles.count > 10 {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    /// Loads all transactions from the journal.
    public func loadAll() throws -> [CleanupTransaction] {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return [] }
        let content = try String(contentsOf: journalURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        return try lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try decoder.decode(CleanupTransaction.self, from: data)
        }
    }
    
    /// Loads all transactions from the journal and archives.
    public func loadAllWithArchives() throws -> [CleanupTransaction] {
        var allTransactions = try loadAll()
        
        if let archiveFiles = try? FileManager.default.contentsOfDirectory(at: archiveDirectoryURL, includingPropertiesForKeys: nil) {
            for archiveURL in archiveFiles where archiveURL.pathExtension == "jsonl" {
                let content = try String(contentsOf: archiveURL, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
                let transactions = try lines.compactMap { line -> CleanupTransaction? in
                    guard let data = line.data(using: .utf8) else { return nil }
                    return try decoder.decode(CleanupTransaction.self, from: data)
                }
                allTransactions.append(contentsOf: transactions)
            }
        }
        
        return allTransactions
    }
    
    /// Clears the transaction journal.
    public func clear() throws {
        if FileManager.default.fileExists(atPath: journalURL.path) {
            try FileManager.default.removeItem(at: journalURL)
        }
    }
    
    /// Clears the journal and all archives.
    public func clearAll() throws {
        try clear()
        if FileManager.default.fileExists(atPath: archiveDirectoryURL.path) {
            try FileManager.default.removeItem(at: archiveDirectoryURL)
            try FileManager.default.createDirectory(at: archiveDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    /// Returns the journal size in bytes.
    public func journalSize() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return 0 }
        let attributes = try FileManager.default.attributesOfItem(atPath: journalURL.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    public enum JournalError: Error, LocalizedError {
        case encodingFailed
        case writeFailed(Error)
        
        public var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode transaction"
            case .writeFailed(let error):
                return "Failed to write to journal: \(error.localizedDescription)"
            }
        }
    }
}
