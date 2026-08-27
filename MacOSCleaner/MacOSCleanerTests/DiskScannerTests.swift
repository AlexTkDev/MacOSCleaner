import XCTest
@testable import MacOSCleaner

final class DiskScannerTests: XCTestCase {
    private var tempDir: URL!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testDiskScanner_scansDirectoryTreeHierarchically() async throws {
        // Create subdirectories
        let docsDir = tempDir.appendingPathComponent("Documents", isDirectory: true)
        let subDocsDir = docsDir.appendingPathComponent("Work", isDirectory: true)
        let mediaDir = tempDir.appendingPathComponent("Media", isDirectory: true)
        
        try FileManager.default.createDirectory(at: subDocsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        // Create dummy files
        let file1 = tempDir.appendingPathComponent("root_file.txt")
        try "Hello World".write(to: file1, atomically: true, encoding: .utf8)
        
        let file2 = docsDir.appendingPathComponent("doc1.pdf")
        try Data(repeating: 0x41, count: 10000).write(to: file2)
        
        let file3 = subDocsDir.appendingPathComponent("work_notes.txt")
        try Data(repeating: 0x42, count: 25000).write(to: file3)
        
        let file4 = mediaDir.appendingPathComponent("video.mp4")
        try Data(repeating: 0x43, count: 50000).write(to: file4)
        
        let scanner = DiskScanner()
        let root = try await scanner.scan(directoryURL: tempDir) { _ in }
        
        XCTAssertEqual(root.url.standardizedFileURL, tempDir.standardizedFileURL)
        XCTAssertTrue(root.isDirectory)
        XCTAssertFalse(root.isPackage)
        XCTAssertGreaterThan(root.size, 0)
        XCTAssertEqual(root.fileCount, 4)
        
        let children = root.children ?? []
        XCTAssertEqual(children.count, 3) // Media, Documents, root_file.txt
        
        // Items sorted by size descending: Media (50KB) > Documents (35KB) > root_file.txt
        XCTAssertEqual(children[0].name, "Media")
        XCTAssertEqual(children[0].fileType, .all)
        XCTAssertEqual(children[0].fileCount, 1)
        
        XCTAssertEqual(children[1].name, "Documents")
        XCTAssertEqual(children[1].fileCount, 2)
        
        // Check nested drill-down under Documents
        let docChildren = children[1].children ?? []
        XCTAssertEqual(docChildren.count, 2) // Work, doc1.pdf
    }
    
    func testDiskScanner_recognizesPackages() async throws {
        let appBundle = tempDir.appendingPathComponent("SampleApp.app", isDirectory: true)
        let contentsDir = appBundle.appendingPathComponent("Contents", isDirectory: true)
        let macosDir = contentsDir.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)
        
        let binary = macosDir.appendingPathComponent("SampleBinary")
        try Data(repeating: 0xAA, count: 30000).write(to: binary)
        
        let scanner = DiskScanner()
        let root = try await scanner.scan(directoryURL: tempDir) { _ in }
        
        let children = root.children ?? []
        XCTAssertEqual(children.count, 1)
        
        let appItem = children[0]
        XCTAssertEqual(appItem.name, "SampleApp.app")
        XCTAssertTrue(appItem.isDirectory)
        XCTAssertTrue(appItem.isPackage)
        XCTAssertEqual(appItem.fileType, .apps)
        XCTAssertGreaterThan(appItem.size, 0)
        XCTAssertNil(appItem.children) // Package internal folders are not expanded as child folders
    }
    
    func testFileCategory_classification() {
        XCTAssertEqual(FileCategory.from(url: URL(fileURLWithPath: "/test/movie.mp4")), .video)
        XCTAssertEqual(FileCategory.from(url: URL(fileURLWithPath: "/test/track.mp3")), .audio)
        XCTAssertEqual(FileCategory.from(url: URL(fileURLWithPath: "/test/photo.jpg")), .photo)
        XCTAssertEqual(FileCategory.from(url: URL(fileURLWithPath: "/test/Test.app")), .apps)
        XCTAssertEqual(FileCategory.from(url: URL(fileURLWithPath: "/test/doc.pdf")), .docs)
        XCTAssertEqual(FileCategory.from(url: URL(fileURLWithPath: "/test/archive.zip")), .archives)
        XCTAssertEqual(FileCategory.from(url: URL(fileURLWithPath: "/test/unknown.xyz")), .all)
    }
    
    @MainActor
    func testDiskAnalyzerViewModel_treeNavigation() async throws {
        let docsDir = tempDir.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        let file = docsDir.appendingPathComponent("test.txt")
        try "test content".write(to: file, atomically: true, encoding: .utf8)
        
        let viewModel = DiskAnalyzerViewModel()
        viewModel.startScan(for: tempDir)
        
        // Wait for scan to finish
        var attempts = 0
        while viewModel.isScanning && attempts < 50 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
        
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertNotNil(viewModel.rootItem)
        XCTAssertEqual(viewModel.pathTrail.count, 1)
        XCTAssertFalse(viewModel.canNavigateUp)
        
        let displayed = viewModel.displayedItems
        XCTAssertEqual(displayed.count, 1)
        XCTAssertEqual(displayed[0].name, "Docs")
        
        // Drill down into Docs
        viewModel.drillDown(into: displayed[0])
        XCTAssertTrue(viewModel.canNavigateUp)
        XCTAssertEqual(viewModel.pathTrail.count, 2)
        XCTAssertEqual(viewModel.currentItem?.name, "Docs")
        XCTAssertEqual(viewModel.displayedItems.count, 1)
        XCTAssertEqual(viewModel.displayedItems[0].name, "test.txt")
        
        // Navigate up
        viewModel.navigateUp()
        XCTAssertFalse(viewModel.canNavigateUp)
        XCTAssertEqual(viewModel.pathTrail.count, 1)
        XCTAssertEqual(viewModel.currentItem?.name, tempDir.lastPathComponent)
    }
    
    @MainActor
    func testDiskAnalyzerViewModel_categoryFiltering() async throws {
        let mediaDir = tempDir.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let videoFile = mediaDir.appendingPathComponent("clip.mov")
        let docFile = mediaDir.appendingPathComponent("readme.pdf")
        try "video bytes".write(to: videoFile, atomically: true, encoding: .utf8)
        try "doc bytes".write(to: docFile, atomically: true, encoding: .utf8)
        
        let viewModel = DiskAnalyzerViewModel()
        viewModel.startScan(for: tempDir)
        
        var attempts = 0
        while viewModel.isScanning && attempts < 50 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
        
        // When .all is selected: shows Media folder
        viewModel.selectedCategory = .all
        XCTAssertEqual(viewModel.displayedItems.count, 1)
        XCTAssertEqual(viewModel.displayedItems[0].name, "Media")
        
        // When .video is selected: recursively finds clip.mov
        viewModel.selectedCategory = .video
        XCTAssertEqual(viewModel.displayedItems.count, 1)
        XCTAssertEqual(viewModel.displayedItems[0].name, "clip.mov")
        XCTAssertEqual(viewModel.displayedItems[0].fileType, .video)
        
        // When .docs is selected: recursively finds readme.pdf
        viewModel.selectedCategory = .docs
        XCTAssertEqual(viewModel.displayedItems.count, 1)
        XCTAssertEqual(viewModel.displayedItems[0].name, "readme.pdf")
        XCTAssertEqual(viewModel.displayedItems[0].fileType, .docs)
        
        // When .photo is selected: returns empty
        viewModel.selectedCategory = .photo
        XCTAssertEqual(viewModel.displayedItems.count, 0)
    }
}
