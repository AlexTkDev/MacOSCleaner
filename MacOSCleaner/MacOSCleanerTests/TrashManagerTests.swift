import XCTest
@testable import MacOSCleaner

final class TrashManagerTests: XCTestCase {
    var trashManager: TrashManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        trashManager = TrashManager()
        let home = NSHomeDirectory()
        tempDirectory = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MacOSCleanerTests_Trash")
        
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
    
    func testTrashItemSuccess() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test_file.txt")
        let testData = "test".data(using: .utf8)!
        try testData.write(to: fileURL)
        
        let trashedURL = try await trashManager.trashItem(at: fileURL)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURL.path))
        
        try? FileManager.default.removeItem(at: trashedURL)
    }
    
    func testTrashProtectedPathThrowsSafetyError() async throws {
        let protectedURL = URL(fileURLWithPath: "/System/Library")
        
        do {
            _ = try await trashManager.trashItem(at: protectedURL)
            XCTFail("Expected SafetyError")
        } catch let safetyError as SafetyError {
            if case .protectedPath(let path) = safetyError {
                XCTAssertEqual(path, "/System")
            } else {
                XCTFail("Expected .protectedPath, got \(safetyError)")
            }
        } catch {
            XCTFail("Expected SafetyError, got \(error)")
        }
    }
    
    func testTrashNonExistentFileThrowsTrashError() async throws {
        let nonExistentURL = tempDirectory.appendingPathComponent("does_not_exist.txt")
        
        do {
            _ = try await trashManager.trashItem(at: nonExistentURL)
            XCTFail("Expected TrashError")
        } catch is TrashError {
            // Expected
        } catch {
            XCTFail("Expected TrashError, got \(error)")
        }
    }
}
