import XCTest
@testable import MacOSCleaner

final class SafetyManagerTests: XCTestCase {

    var safetyManager: SafetyManager!
    var home: String!

    override func setUp() {
        super.setUp()
        safetyManager = SafetyManager()
        home = NSHomeDirectory()
    }

    override func tearDown() {
        safetyManager = nil
        super.tearDown()
    }

    func testSafePaths() throws {
        let safePaths = [
            "\(home!)/Library/Caches/com.example.app",
            "\(home!)/Downloads/test_file.txt",
            "/Users/Shared/cache_folder"
        ]

        for path in safePaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url), "Path \(path) should be valid")
        }
    }

    func testProtectedSystemPaths() {
        let protectedPaths = [
            ("/", "/"),
            ("/System/Library/CoreServices", "/System"),
            ("/Library/Preferences/SystemConfiguration", "/Library"),
            ("/usr/local/bin", "/usr"),
            ("/bin/ls", "/bin"),
            ("/private/etc/hosts", "/etc") // On macOS /private/etc resolves to /etc when standardized
        ]

        for (path, refused) in protectedPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Path \(path) should be rejected as \(refused)") { error in
                XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath(refused))
            }
        }
    }

    func testProtectedUserPaths() {
        let protectedPaths = [
            ("\(home!)/.ssh/id_rsa", "\(home!)/.ssh"),
            ("\(home!)/.gnupg/pubring.kbx", "\(home!)/.gnupg"),
            ("\(home!)/Documents/Work/file.txt", "\(home!)/Documents")
        ]

        for (path, refused) in protectedPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url)) { error in
                XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath(refused))
            }
        }
    }

    func testSymlinkEscape() throws {
        // Create a symlink pointing to a protected directory in a safe location
        let home = NSHomeDirectory()
        let tempDir = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MacOSCleanerTests_Safety")
        
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let symlinkURL = tempDir.appendingPathComponent("fake_cache")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: "/System"))

        // The symlink itself is in a safe directory, but it points to a protected one
        XCTAssertThrowsError(try safetyManager.validate(url: symlinkURL)) { error in
            XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath("/System"))
        }

        try FileManager.default.removeItem(at: symlinkURL)
        try FileManager.default.removeItem(at: tempDir)
    }

    func testPathNormalization() {
        let maliciousPath = "/Users/Shared/../../System/Library"
        let url = URL(fileURLWithPath: maliciousPath)
        
        XCTAssertThrowsError(try safetyManager.validate(url: url)) { error in
            XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath("/System"))
        }
    }
}
