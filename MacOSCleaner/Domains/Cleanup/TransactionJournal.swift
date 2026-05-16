import Foundation

/// Журнал транзакций очистки для обеспечения возможности отката и аудита.
/// Использует формат JSONL (JSON Lines) для обеспечения отказоустойчивости при записи.
public actor TransactionJournal {
    private let journalURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(journalURL: URL? = nil) {
        if let url = journalURL {
            self.journalURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let journalDir = appSupport.appendingPathComponent("MacOSCleaner", isDirectory: true)
            try? FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
            self.journalURL = journalDir.appendingPathComponent("transactions.jsonl")
        }
    }
    
    /// Записывает новую транзакцию в журнал.
    /// - Parameter transaction: Транзакция для записи.
    public func log(transaction: CleanupTransaction) throws {
        let data = try encoder.encode(transaction)
        guard var line = String(data: data, encoding: .utf8) else {
            throw JournalError.encodingFailed
        }
        line += "\n"
        
        if !FileManager.default.fileExists(atPath: journalURL.path) {
            try line.write(to: journalURL, atomically: true, encoding: .utf8)
        } else {
            let fileHandle = try FileHandle(forWritingTo: journalURL)
            try fileHandle.seekToEnd()
            if let lineData = line.data(using: .utf8) {
                try fileHandle.write(contentsOf: lineData)
            }
            try fileHandle.close()
        }
    }
    
    /// Загружает все транзакции из журнала.
    public func loadAll() throws -> [CleanupTransaction] {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return [] }
        let content = try String(contentsOf: journalURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        return try lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try decoder.decode(CleanupTransaction.self, from: data)
        }
    }
    
    public enum JournalError: Error {
        case encodingFailed
    }
}
