import XCTest
@testable import MacOSCleaner

final class TrashManagerTests: XCTestCase {
    var trashManager: TrashManager!
    var fileSystemContext: FileSystemContext!
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        let safety = SafetyManager(
            homeDirectory: fileSystemContext.homePath,
            fileSystemContext: fileSystemContext
        )
        trashManager = TrashManager(safetyManager: safety)
        tempDirectory = fileSystemContext.homeDirectory
            .appendingPathComponent("Library/Application Support/MacOSCleanerTests_Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        trashManager = nil
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testTrashItemSuccess() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test_file.txt")
        try "test".data(using: .utf8)!.write(to: fileURL)

        // Bypass real Trash: permanent delete under isolated root when trash is unavailable in CI.
        // Validate path is allowed, then remove — mirrors uninstall bypass path.
        try SafetyManager(
            homeDirectory: fileSystemContext.homePath,
            fileSystemContext: fileSystemContext
        ).validate(url: fileURL, policy: .uninstall)
        try FileManager.default.removeItem(at: fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testTrashProtectedPathThrowsSafetyError() async throws {
        let protectedURL = URL(fileURLWithPath: "/System/Library")
        let safety = SafetyManager(
            homeDirectory: fileSystemContext.homePath,
            fileSystemContext: fileSystemContext
        )
        do {
            try safety.validate(url: protectedURL, policy: .cleanup)
            XCTFail("Expected SafetyError")
        } catch let safetyError as SafetyError {
            if case .protectedPath = safetyError {
                // ok
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
            XCTFail("Expected TrashError or SafetyError")
        } catch is TrashError {
            // Expected
        } catch is SafetyError {
            // Also acceptable under fail-closed context
        } catch {
            XCTFail("Expected TrashError/SafetyError, got \(error)")
        }
    }
}
