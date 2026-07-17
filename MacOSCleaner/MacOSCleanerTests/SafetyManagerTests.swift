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
            "/Users/Shared/cache_folder",
            "/usr/local/bin/app_tool"
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

    func testNoHardcodedDeveloperPaths() {
        let home = NSHomeDirectory()
        let developerPath = "\(home)/Documents/my/macos-cleaner/build"
        let url = URL(fileURLWithPath: developerPath)
        
        XCTAssertThrowsError(try safetyManager.validate(url: url), "Developer path should not be allowed by default") { error in
            XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath("\(home)/Documents"))
        }
    }

    func testCustomAllowedExceptions() {
        let home = NSHomeDirectory()
        let customPath = "\(home)/Documents/my/macos-cleaner/build"
        let managerWithException = SafetyManager(allowedExceptions: [customPath])
        let url = URL(fileURLWithPath: customPath)
        
        XCTAssertNoThrow(try managerWithException.validate(url: url), "Custom exception should allow the path")
    }

    func testDefaultExceptionsStillWork() {
        let home = NSHomeDirectory()
        let defaultExceptionPath = "\(home)/Library/Caches/test"
        let url = URL(fileURLWithPath: defaultExceptionPath)
        
        XCTAssertNoThrow(try safetyManager.validate(url: url), "Default exceptions should still work")
    }

    func testSensitiveUserDataProtectedDespiteLibraryException() {
        let sensitive = [
            "\(home!)/Library/Keychains/login.keychain-db",
            "\(home!)/Library/Calendars/Calendar.sqlitedb",
            "\(home!)/Library/Reminders/Container_v1",
            "\(home!)/Library/Application Support/AddressBook/AddressBook-v22.abcddb",
            "\(home!)/Library/Application Support/Google/Chrome/Default/Login Data",
        ]
        for path in sensitive {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Sensitive path \(path) must be protected")
        }
    }

    func testLibraryRootsNotDeletableWholesale() {
        let roots = [
            "\(home!)",
            "\(home!)/Library",
            "\(home!)/Library/Preferences",
            "\(home!)/Library/Application Support",
            "\(home!)/Library/Group Containers",
            "\(home!)/Library/Containers",
        ]
        for path in roots {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Root \(path) must not be deletable wholesale")
        }
    }

    func testChildrenOfProtectedRootsStillDeletable() {
        let children = [
            "\(home!)/Library/Preferences/com.example.app.plist",
            "\(home!)/Library/Group Containers/group.com.example.app",
            "\(home!)/Library/Application Support/ExampleApp",
            "/Library/LaunchAgents/com.example.agent.plist",
        ]
        for path in children {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url), "Child \(path) must remain deletable")
        }
    }

    func testCleanupBlocksBrowserUserDataPaths() {
        let blocked = [
            "\(home!)/Library/Application Support/Google/Chrome",
            "\(home!)/Library/Application Support/Google/Chrome/Default",
            "\(home!)/Library/Application Support/Google/Chrome/Default/Login Data",
            "\(home!)/Library/Application Support/Google/Chrome/Default/Network/Cookies",
            "\(home!)/Library/Application Support/Google/Chrome/Profile 1/Cookies",
            // Ancestor whose removal would take the profile root with it
            "\(home!)/Library/Application Support/Google",
            "\(home!)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Web Data",
            "\(home!)/Library/Application Support/Firefox/Profiles/abcd.default-release/logins.json",
        ]
        for path in blocked {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Cleanup must not delete \(path)")
        }
    }

    func testCleanupAllowsBrowserCacheSubdirectories() {
        let allowed = [
            "\(home!)/Library/Application Support/Google/Chrome/Default/Cache",
            "\(home!)/Library/Application Support/Google/Chrome/Default/Code Cache/js",
            "\(home!)/Library/Application Support/Google/Chrome/GrShaderCache",
            "\(home!)/Library/Application Support/Google/Chrome/Crashpad",
            "\(home!)/Library/Application Support/Firefox/Profiles/abcd.default-release/cache2",
        ]
        for path in allowed {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url), "Cleanup must allow cache path \(path)")
        }
    }

    func testUninstallPolicyAllowsBrowserUserDataRemoval() {
        let allowed = [
            "\(home!)/Library/Application Support/Google/Chrome",
            "\(home!)/Library/Application Support/Google/Chrome/Default",
            "\(home!)/Library/Application Support/Google",
        ]
        for path in allowed {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url, policy: .uninstall), "Uninstall must allow \(path)")
        }
        // Credential files stay hard-protected even during uninstall
        let loginData = URL(fileURLWithPath: "\(home!)/Library/Application Support/Google/Chrome/Default/Login Data")
        XCTAssertThrowsError(try safetyManager.validate(url: loginData, policy: .uninstall))
    }

    func testCleanupBlocksCredentialFilesInApplicationSupport() {
        let blocked = [
            "\(home!)/Library/Application Support/Slack/Cookies",
            "\(home!)/Library/Application Support/Slack/Cookies-journal",
            "\(home!)/Library/Application Support/SomeApp/Login Data",
            "\(home!)/Library/Application Support/SomeApp/Local State",
        ]
        for path in blocked {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Cleanup must not delete \(path)")
        }
        let cache = URL(fileURLWithPath: "\(home!)/Library/Application Support/Slack/Cache")
        XCTAssertNoThrow(try safetyManager.validate(url: cache))
    }

    func testVirtualizationUserDataUnderDocumentsAllowed() {
        let vmPath = "\(home!)/Documents/my_project/Orbstack_files"
        let url = URL(fileURLWithPath: vmPath)
        XCTAssertNoThrow(try safetyManager.validate(url: url))
    }

    func testNonVMDataUnderDocumentsStillProtected() {
        let path = "\(home!)/Documents/my_project/source.swift"
        let url = URL(fileURLWithPath: path)
        XCTAssertThrowsError(try safetyManager.validate(url: url))
    }
}
