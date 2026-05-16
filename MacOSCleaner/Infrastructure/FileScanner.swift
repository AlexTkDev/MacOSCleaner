import Foundation

public actor FileScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Scans directories recursively and returns URLs in batches.
    /// - Parameters:
    ///   - urls: The base URLs to start scanning from.
    ///   - batchSize: The maximum number of URLs to return in a single yield.
    ///   - throttleInterval: The minimum time between yields to prevent overwhelming the consumer.
    /// - Returns: An AsyncStream of URL batches.
    public nonisolated func scan(urls: [URL], batchSize: Int = 100, throttleInterval: TimeInterval = 0.05) -> AsyncStream<[URL]> {
        AsyncStream { continuation in
            let task = Task {
                var currentBatch: [URL] = []
                currentBatch.reserveCapacity(batchSize)
                
                var lastYieldTime = Date()
                
                for url in urls {
                    if Task.isCancelled { break }
                    
                    // We only scan directories; if it's a file, we just yield it directly.
                    var isDirectory: ObjCBool = false
                    guard self.fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                        continue
                    }
                    
                    if !isDirectory.boolValue {
                        currentBatch.append(url)
                        continue
                    }
                    
                    guard let enumerator = self.fileManager.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: []
                    ) else {
                        continue
                    }
                    
                    for case let fileURL as URL in enumerator {
                        if Task.isCancelled { break }
                        
                        currentBatch.append(fileURL)
                        
                        let now = Date()
                        if currentBatch.count >= batchSize || now.timeIntervalSince(lastYieldTime) >= throttleInterval {
                            continuation.yield(currentBatch)
                            currentBatch.removeAll(keepingCapacity: true)
                            lastYieldTime = now
                            
                            // Yield to the system to avoid blocking the thread for too long
                            await Task.yield()
                        }
                    }
                }
                
                if !currentBatch.isEmpty && !Task.isCancelled {
                    continuation.yield(currentBatch)
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
