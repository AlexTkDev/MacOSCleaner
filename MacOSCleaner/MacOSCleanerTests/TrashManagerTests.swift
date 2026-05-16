import XCTest
@testable import MacOSCleaner

final class TrashManagerTests: XCTestCase {
    var trashManager: TrashManager!
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        trashManager = TrashManager()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }
    
    func testTrashItemSuccess() throws {
        let fileURL = tempDirectory.appendingPathComponent("test_file.txt")
        let testData = "test".data(using: .utf8)!
        try testData.write(to: fileURL)
        
        let trashedURL = try trashManager.trashItem(at: fileURL)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURL.path))
        
        try? FileManager.default.removeItem(at: trashedURL)
    }
    
    func testTrashProtectedPathThrowsSafetyError() throws {
        let protectedURL = URL(fileURLWithPath: "/System/Library")
        
        XCTAssertThrowsError(try trashManager.trashItem(at: protectedURL)) { error in
            guard let safetyError = error as? SafetyError else {
                XCTFail("Expected SafetyError, got \(error)")
                return
            }
            if case .protectedPath(let path) = safetyError {
                XCTAssertEqual(path, "/System")
            } else {
                XCTFail("Expected .protectedPath, got \(safetyError)")
            }
        }
    }
    
    func testTrashNonExistentFileThrowsTrashError() throws {
        let nonExistentURL = tempDirectory.appendingPathComponent("does_not_exist.txt")
        
        XCTAssertThrowsError(try trashManager.trashItem(at: nonExistentURL)) { error in
            XCTAssertTrue(error is TrashError)
        }
    }
}
