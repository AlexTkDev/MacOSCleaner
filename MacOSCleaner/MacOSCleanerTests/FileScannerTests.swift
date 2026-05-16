import XCTest
@testable import MacOSCleaner

final class FileScannerTests: XCTestCase {
    var scanner: FileScanner!
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        scanner = FileScanner()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }
    
    func testRecursiveScanning() async throws {
        // Create a nested directory structure
        let dir1 = tempDirectory.appendingPathComponent("dir1")
        let dir2 = dir1.appendingPathComponent("dir2")
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        let file1 = dir1.appendingPathComponent("file1.txt")
        let file2 = dir2.appendingPathComponent("file2.txt")
        
        try "test".data(using: .utf8)!.write(to: file1)
        try "test".data(using: .utf8)!.write(to: file2)
        
        let stream = scanner.scan(urls: [tempDirectory])
        var foundURLs: Set<URL> = []
        
        for await batch in stream {
            foundURLs.formUnion(batch)
        }
        
        XCTAssertTrue(foundURLs.contains(dir1))
        XCTAssertTrue(foundURLs.contains(dir2))
        XCTAssertTrue(foundURLs.contains(file1))
        XCTAssertTrue(foundURLs.contains(file2))
    }
    
    func testBatching() async throws {
        // Create 5 files
        for i in 0..<5 {
            let fileURL = tempDirectory.appendingPathComponent("file\(i).txt")
            try "test".data(using: .utf8)!.write(to: fileURL)
        }
        
        // Scan with batch size 2
        let stream = scanner.scan(urls: [tempDirectory], batchSize: 2)
        var batchSizes: [Int] = []
        var totalCount = 0
        
        for await batch in stream {
            batchSizes.append(batch.count)
            totalCount += batch.count
        }
        
        // Should yield batches of sizes like [2, 2, 1] for the 5 files, 
        // but there's also the tempDirectory itself if we included it, but wait, 
        // the enumerator doesn't yield the root directory, so it's just the 5 files.
        XCTAssertEqual(totalCount, 5)
        XCTAssertTrue(batchSizes.contains(2))
    }
    
    func testCancellation() async throws {
        // Create 1000 files to ensure scan takes enough time to cancel
        for i in 0..<1000 {
            let fileURL = tempDirectory.appendingPathComponent("file\(i).txt")
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        
        let task = Task<Int, Never> {
            var count = 0
            let stream = scanner.scan(urls: [tempDirectory], batchSize: 10)
            for await batch in stream {
                count += batch.count
            }
            return count
        }
        
        // Give it a tiny bit of time to start, then cancel
        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        
        let count = await task.value
        // If cancellation worked, it shouldn't have scanned all 1000 items
        XCTAssertLessThan(count, 1000)
    }
}
