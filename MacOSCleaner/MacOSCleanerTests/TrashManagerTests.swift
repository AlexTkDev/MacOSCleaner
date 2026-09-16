import XCTest
@testable import MacOSCleaner

final class TrashManagerTests: XCTestCase {
    var trashManager: TrashManager!
    var fileSystemContext: FileSystemContext!
    var tempDirectory: URL!
    var trashDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        let safety = SafetyManager(
            homeDirectory: fileSystemContext.homePath,
            fileSystemContext: fileSystemContext
        )
        trashDirectory = fileSystemContext.homeDirectory
            .appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        trashManager = TrashManager(safetyManager: safety, trashDirectoryURL: trashDirectory)
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
        trashDirectory = nil
        try super.tearDownWithError()
    }

    func testTrashItemSuccess() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test_file.txt")
        try "test".data(using: .utf8)!.write(to: fileURL)

        let trashed = try await trashManager.trashItem(at: fileURL, policy: .cleanup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
        XCTAssertEqual(trashed.deletingLastPathComponent().path, trashDirectory.path)
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

    func testPermanentlyDeleteSuccess() async throws {
        let fileURL = trashDirectory.appendingPathComponent("perm_delete_test.txt")
        guard let data = "hello world".data(using: .utf8) else {
            XCTFail("Data encoding failed")
            return
        }
        try data.write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let freed = try await trashManager.permanentlyDelete(urls: [fileURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertGreaterThan(freed, 0)
    }

    func testPermanentlyDeleteDirectory() async throws {
        let subDir = trashDirectory.appendingPathComponent("subfolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let fileInside = subDir.appendingPathComponent("file.bin")
        try Data(repeating: 0x42, count: 1024).write(to: fileInside)

        XCTAssertTrue(FileManager.default.fileExists(atPath: subDir.path))
        let freed = try await trashManager.permanentlyDelete(urls: [subDir])
        XCTAssertFalse(FileManager.default.fileExists(atPath: subDir.path))
        XCTAssertGreaterThanOrEqual(freed, 1024)
    }

    func testPermanentlyDeleteSelectiveDoesNotTouchOtherFilesInTrash() async throws {
        let fileToDelete = trashDirectory.appendingPathComponent("delete_me.txt")
        let thirdPartyFile = trashDirectory.appendingPathComponent("keep_me_finder.txt")
        try "delete".data(using: .utf8)!.write(to: fileToDelete)
        try "keep".data(using: .utf8)!.write(to: thirdPartyFile)

        let freed = try await trashManager.permanentlyDelete(urls: [fileToDelete])
        XCTAssertGreaterThan(freed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileToDelete.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thirdPartyFile.path), "Unrelated files in Trash must never be deleted")
    }

    func testPermanentlyDeleteRefusesTrashFolderItself() async throws {
        let freed = try await trashManager.permanentlyDelete(urls: [trashDirectory])
        XCTAssertEqual(freed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDirectory.path), ".Trash folder itself must never be removed")
    }

    func testPermanentlyDeleteRefusesSystemTrashFolderItself() async throws {
        let systemTrash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let freed = try await trashManager.permanentlyDelete(urls: [systemTrash])
        XCTAssertEqual(freed, 0)
    }

    func testEmptyTrashWholesaleThrows() async {
        do {
            _ = try await trashManager.emptyTrash()
            XCTFail("Expected wholesale emptyTrash to throw")
        } catch is TrashError {
            // Expected
        } catch {
            XCTFail("Expected TrashError, got \(error)")
        }
    }
}
