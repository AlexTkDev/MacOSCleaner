import XCTest
@testable import MacOSCleaner

final class DiskScannerTests: XCTestCase {
    var scanner: DiskScanner!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        scanner = DiskScanner()
        let home = NSHomeDirectory()
        tempDirectory = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MacOSCleanerTests_DiskScanner")
        
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }
    
    func testDirectoryScanningAndSizes() async throws {
        // Create folder structure
        let dir1 = tempDirectory.appendingPathComponent("Movies")
        let dir2 = tempDirectory.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        // 1.5 MB video file (1,572,864 bytes)
        let fileVideo = dir1.appendingPathComponent("video.mp4")
        let videoData = Data(repeating: 0, count: 1024 * 1024 + 512 * 1024)
        try videoData.write(to: fileVideo)
        
        // 300 KB text document (307,200 bytes)
        let fileDoc = dir2.appendingPathComponent("document.docx")
        let docData = Data(repeating: 0, count: 300 * 1024)
        try docData.write(to: fileDoc)
        
        // Scan tempDirectory
        let items = try await scanner.scan(directoryURL: tempDirectory) { _ in }
        
        XCTAssertEqual(items.count, 2)
        
        let moviesItem = items.first { $0.name == "Movies" }
        XCTAssertNotNil(moviesItem)
        XCTAssertTrue(moviesItem?.isDirectory ?? false)
        XCTAssertEqual(moviesItem?.size, Int64(videoData.count))
        
        let docsItem = items.first { $0.name == "Documents" }
        XCTAssertNotNil(docsItem)
        XCTAssertTrue(docsItem?.isDirectory ?? false)
        XCTAssertEqual(docsItem?.size, Int64(docData.count))
    }
    
    func testFileClassification() {
        let videoURL = URL(fileURLWithPath: "/path/to/movie.mov")
        let audioURL = URL(fileURLWithPath: "/path/to/song.mp3")
        let appURL = URL(fileURLWithPath: "/path/to/app.app")
        let docURL = URL(fileURLWithPath: "/path/to/resume.pdf")
        let devURL = URL(fileURLWithPath: "/path/to/code.swift")
        
        XCTAssertEqual(FileCategory.from(url: videoURL), .video)
        XCTAssertEqual(FileCategory.from(url: audioURL), .audio)
        XCTAssertEqual(FileCategory.from(url: appURL), .apps)
        XCTAssertEqual(FileCategory.from(url: docURL), .docs)
        XCTAssertEqual(FileCategory.from(url: devURL), .all)
    }
}
