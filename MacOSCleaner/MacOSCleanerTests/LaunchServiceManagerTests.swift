import XCTest
@testable import MacOSCleaner

final class LaunchServiceManagerTests: XCTestCase {
    var manager: LaunchServiceManager!
    var tempDir: URL!
    var fileManager: FileManager!
    
    override func setUp() async throws {
        fileManager = .default
        let home = NSHomeDirectory()
        tempDir = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MacOSCleanerTests")
        
        if fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.removeItem(at: tempDir)
        }
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        manager = LaunchServiceManager(searchPaths: [tempDir.path])
    }
    
    override func tearDown() async throws {
        if fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.removeItem(at: tempDir)
        }
        manager = nil
    }
    
    func testScanDetectsPlists() async throws {
        // Create a dummy plist
        let plistURL = tempDir.appendingPathComponent("com.test.agent.plist")
        let plistContent: [String: Any] = ["Label": "com.test.agent"]
        let data = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
        try data.write(to: plistURL)
        
        let services = try await manager.scan()
        
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services.first?.id, "com.test.agent")
        XCTAssertEqual(services.first?.path, plistURL.path)
    }
    
    func testScanFiltersNonPlists() async throws {
        // Create a non-plist file
        let txtURL = tempDir.appendingPathComponent("not_a_plist.txt")
        try "test".write(to: txtURL, atomically: true, encoding: .utf8)
        
        let services = try await manager.scan()
        XCTAssertTrue(services.isEmpty)
    }
    
    func testScanSortsByName() async throws {
        let plist1 = tempDir.appendingPathComponent("b.plist")
        let plist2 = tempDir.appendingPathComponent("a.plist")
        
        let data1 = try PropertyListSerialization.data(fromPropertyList: ["Label": "b"], format: .xml, options: 0)
        let data2 = try PropertyListSerialization.data(fromPropertyList: ["Label": "a"], format: .xml, options: 0)
        
        try data1.write(to: plist1)
        try data2.write(to: plist2)
        
        let services = try await manager.scan()
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].id, "a")
        XCTAssertEqual(services[1].id, "b")
    }

    func testScanDetectsMultiplePaths() async throws {
        let dir1 = tempDir.appendingPathComponent("path1")
        let dir2 = tempDir.appendingPathComponent("path2")
        try fileManager.createDirectory(at: dir1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        let plist1 = dir1.appendingPathComponent("1.plist")
        let plist2 = dir2.appendingPathComponent("2.plist")
        
        try PropertyListSerialization.data(fromPropertyList: ["Label": "1"], format: .xml, options: 0).write(to: plist1)
        try PropertyListSerialization.data(fromPropertyList: ["Label": "2"], format: .xml, options: 0).write(to: plist2)
        
        let multiManager = LaunchServiceManager(searchPaths: [dir1.path, dir2.path])
        let services = try await multiManager.scan()
        
        XCTAssertEqual(services.count, 2)
        let labels = Set(services.map { $0.id })
        XCTAssertTrue(labels.contains("1"))
        XCTAssertTrue(labels.contains("2"))
    }
}
