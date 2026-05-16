import Foundation

public actor FileScanner {
    public init() {}

    /// Scans directories recursively and returns URLs in batches.
    /// - Parameters:
    ///   - urls: The base URLs to start scanning from.
    ///   - batchSize: The maximum number of URLs to return in a single yield.
    ///   - throttleInterval: The minimum time between yields to prevent overwhelming the consumer.
    /// - Returns: An AsyncStream of URL batches.
    public nonisolated func scan(urls: [URL], batchSize: Int = 100, throttleInterval: TimeInterval = 0.05) -> AsyncStream<[URL]> {
        AsyncStream { continuation in
            let task = Task {
                let fm = FileManager.default
                var currentBatch: [URL] = []
                currentBatch.reserveCapacity(batchSize)
                
                var lastYieldTime = Date()
                
                for url in urls {
                    if Task.isCancelled { break }
                    
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                        continue
                    }
                    
                    if !isDirectory.boolValue {
                        currentBatch.append(url)
                        continue
                    }
                    
                    guard let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: []
                    ) else {
                        continue
                    }
                    
                    while let fileURL = enumerator.nextObject() as? URL {
                        if Task.isCancelled { break }
                        
                        currentBatch.append(fileURL)
                        
                        let now = Date()
                        if currentBatch.count >= batchSize || now.timeIntervalSince(lastYieldTime) >= throttleInterval {
                            continuation.yield(currentBatch)
                            currentBatch.removeAll(keepingCapacity: true)
                            lastYieldTime = now
                            
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
