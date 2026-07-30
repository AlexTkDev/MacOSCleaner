import XCTest
@testable import MacOSCleaner

final class SafetyManagerTests: XCTestCase {
    private var fileSystemContext: FileSystemContext!
    private var safetyManager: SafetyManager!
    private var home: String = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        home = fileSystemContext.homePath
        // Policy tests use isolated home paths without enforceAllowedRoots so
        // assertions target refuse/exception rules, not the test-root gate.
        safetyManager = SafetyManager(homeDirectory: home)
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        safetyManager = nil
        home = ""
        try super.tearDownWithError()
    }

    func testSafePaths() throws {
        let safePaths = [
            "\(home)/Library/Caches/com.example.app",
            "\(home)/Library/Developer/Xcode/DerivedData/project",
            "\(home)/Library/Application Support/com.example.app",
        ]

        for path in safePaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url), "Path \(path) should be valid")
        }
    }

    func testProtectedSystemPaths() {
        let protectedPaths = [
            ("\(home)/", "\(home)"),
            ("\(home)/Library", "\(home)/Library"),
            ("\(home)/Library/Preferences", "\(home)/Library/Preferences"),
            ("\(home)/Library/Application Support", "\(home)/Library/Application Support"),
            ("\(home)/Library/Group Containers", "\(home)/Library/Group Containers"),
            ("\(home)/Library/Containers", "\(home)/Library/Containers"),
            ("\(home)/Backups", "\(home)/Backups"),
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
            ("\(home)/.ssh/id_rsa", "\(home)/.ssh"),
            ("\(home)/.gnupg/pubring.kbx", "\(home)/.gnupg"),
            ("\(home)/Documents/Work/file.txt", "\(home)/Documents"),
            ("\(home)/Desktop/file.txt", "\(home)/Desktop"),
            ("\(home)/Downloads/file.txt", "\(home)/Downloads")
        ]

        for (path, refused) in protectedPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url)) { error in
                XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath(refused))
            }
        }
    }

    func testReviewableBackupLeafAllowedUnderPersonalRoots() throws {
        let allowed = [
            "\(home)/Desktop/project.backup",
            "\(home)/Documents/notes.bak",
            "\(home)/Downloads/old.old",
        ]
        for path in allowed {
            XCTAssertNoThrow(try safetyManager.validate(url: URL(fileURLWithPath: path), policy: .cleanup))
        }
        // Nested under Documents still refused; ~/Backups never allowed.
        XCTAssertThrowsError(try safetyManager.validate(url: URL(fileURLWithPath: "\(home)/Documents/Work/x.backup")))
        XCTAssertThrowsError(try safetyManager.validate(url: URL(fileURLWithPath: "\(home)/Backups/x.backup")))
    }

    func testSymlinkEscape() throws {
        // Create a symlink pointing to a protected directory in a safe location
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

    func testLeafSymlinkIsAllowed() throws {
        let tempDir = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MacOSCleanerTests_LeafSymlink")
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let target = tempDir.appendingPathComponent("target.txt")
        try Data("leaf".utf8).write(to: target)
        let symlinkURL = tempDir.appendingPathComponent("leaf_link.txt")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: target)

        XCTAssertNoThrow(try safetyManager.validate(url: symlinkURL))
    }

    func testPathNormalization() {
        let maliciousPath = "\(home)/Library/Application Support/../../Library"
        let url = URL(fileURLWithPath: maliciousPath)
        
        XCTAssertThrowsError(try safetyManager.validate(url: url)) { error in
            XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath("\(home)/Library"))
        }
    }

    func testNoHardcodedDeveloperPaths() {
        // Non-artifact path under Documents must stay protected (source files, not build/).
        let developerPath = "\(home)/Documents/my/macos-cleaner/Sources"
        let url = URL(fileURLWithPath: developerPath)
        
        XCTAssertThrowsError(try safetyManager.validate(url: url), "Developer source path should not be allowed by default") { error in
            XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath("\(home)/Documents"))
        }
    }

    func testCustomAllowedExceptions() {
        // Custom exceptions must not override hard-refused user content roots.
        let customPath = "\(home)/Documents/my/macos-cleaner/Sources"
        let managerWithException = SafetyManager(
            allowedExceptions: [customPath],
            homeDirectory: home
        )
        let url = URL(fileURLWithPath: customPath)
        XCTAssertThrowsError(try managerWithException.validate(url: url))

        // Custom exception under Library still works.
        let libPath = "\(home)/Library/Application Support/CustomTool/data"
        let libManager = SafetyManager(
            allowedExceptions: ["\(home)/Library/Application Support/CustomTool"],
            homeDirectory: home
        )
        XCTAssertNoThrow(try libManager.validate(url: URL(fileURLWithPath: libPath)))
    }

    func testDefaultExceptionsStillWork() {
        let defaultExceptionPath = "\(home)/Library/Caches/test"
        let url = URL(fileURLWithPath: defaultExceptionPath)
        
        XCTAssertNoThrow(try safetyManager.validate(url: url), "Default exceptions should still work")
    }

    func testSensitiveUserDataProtectedDespiteLibraryException() {
        let sensitive = [
            "\(home)/Library/Keychains/login.keychain-db",
            "\(home)/Library/Calendars/Calendar.sqlitedb",
            "\(home)/Library/Reminders/Container_v1",
            "\(home)/Library/Application Support/AddressBook/AddressBook-v22.abcddb",
            "\(home)/Library/Messages/Attachments",
            "\(home)/Library/Google/GoogleSoftwareUpdate",
            "\(home)/Library/Preferences/com.google.Keystone.Agent.plist",
            "\(home)/Library/Caches/com.google.SoftwareUpdate",
            "\(home)/Library/Caches/com.google.GoogleUpdater",
            "\(home)/Library/HTTPStorages/com.google.GoogleUpdater",
            "\(home)/Library/Application Support/Google/GoogleUpdater",
            "\(home)/Library/LaunchAgents/com.google.keystone.agent.plist",
            "\(home)/Library/Application Support/Google/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Google/Chrome/Default/Cookies",
            "\(home)/Library/Application Support/Google/Chrome/Default/Local State",
            "\(home)/Library/Application Support/Google/Chrome/Default/Web Data",
        ]
        for path in sensitive {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Sensitive path \(path) must be protected")
        }
    }

    func testLibraryRootsNotDeletableWholesale() {
        let roots = [
            "\(home)",
            "\(home)/Backups",
            "\(home)/Library",
            "\(home)/Library/Preferences",
            "\(home)/Library/Application Support",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Containers",
        ]
        for path in roots {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Root \(path) must not be deletable wholesale")
        }
    }

    func testChildrenOfProtectedRootsStillDeletable() {
        let children = [
            "\(home)/Library/Preferences/com.example.app.plist",
            "\(home)/Library/Group Containers/group.com.example.app",
            "\(home)/Library/Application Support/ExampleApp",
            "\(home)/Library/LaunchAgents/com.example.agent.plist",
        ]
        for path in children {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url), "Child \(path) must remain deletable")
        }
    }

    func testCleanupBlocksBrowserUserDataPaths() {
        let blocked = [
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Google/Chrome/Default",
            "\(home)/Library/Application Support/Google/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Google/Chrome/Default/Network/Cookies",
            "\(home)/Library/Application Support/Google/Chrome/Profile 1/Cookies",
            // Ancestor whose removal would take the profile root with it
            "\(home)/Library/Application Support/Google",
            "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Web Data",
            "\(home)/Library/Application Support/Firefox/Profiles/abcd.default-release/logins.json",
            "\(home)/Library/Application Support/Arc/User Data/Default/History",
        ]
        for path in blocked {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Cleanup must not delete \(path)")
        }
    }

    func testCleanupAllowsBrowserCacheSubdirectories() {
        let allowed = [
            "\(home)/Library/Application Support/Google/Chrome/Default/Cache",
            "\(home)/Library/Application Support/Google/Chrome/Default/Code Cache/js",
            "\(home)/Library/Application Support/Google/Chrome/GrShaderCache",
            "\(home)/Library/Application Support/Google/Chrome/Crashpad",
            "\(home)/Library/Application Support/Firefox/Profiles/abcd.default-release/cache2",
        ]
        for path in allowed {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url), "Cleanup must allow cache path \(path)")
        }
    }

    func testUninstallPolicyAllowsBrowserUserDataRemoval() {
        let allowed = [
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Google/Chrome/Default",
            "\(home)/Library/Application Support/Google",
        ]
        for path in allowed {
            let url = URL(fileURLWithPath: path)
            XCTAssertNoThrow(try safetyManager.validate(url: url, policy: .uninstall), "Uninstall must allow \(path)")
        }
        // Credential files stay hard-protected even during uninstall
        let loginData = URL(fileURLWithPath: "\(home)/Library/Application Support/Google/Chrome/Default/Login Data")
        XCTAssertThrowsError(try safetyManager.validate(url: loginData, policy: .uninstall))
    }

    func testCleanupBlocksCredentialFilesInApplicationSupport() {
        let blocked = [
            "\(home)/Library/Application Support/Slack/Cookies",
            "\(home)/Library/Application Support/Slack/Cookies-journal",
            "\(home)/Library/Application Support/SomeApp/Login Data",
            "\(home)/Library/Application Support/SomeApp/Local State",
        ]
        for path in blocked {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Cleanup must not delete \(path)")
        }
        let cache = URL(fileURLWithPath: "\(home)/Library/Application Support/Slack/Cache")
        XCTAssertNoThrow(try safetyManager.validate(url: cache))
    }

    func testVirtualizationUserDataUnderDocumentsStillProtected() {
        let vmPath = "\(home)/Documents/my_project/Orbstack_files"
        let url = URL(fileURLWithPath: vmPath)
        XCTAssertThrowsError(try safetyManager.validate(url: url))
    }

    func testNonVMDataUnderDocumentsStillProtected() {
        let path = "\(home)/Documents/my_project/source.swift"
        let url = URL(fileURLWithPath: path)
        XCTAssertThrowsError(try safetyManager.validate(url: url))
    }

    func testProjectLocalBuildArtifactUnderDocumentsAllowed() {
        let build = URL(fileURLWithPath: "\(home)/Documents/my_project/build")
        let derived = URL(fileURLWithPath: "\(home)/Developer/Foo/DerivedData")
        XCTAssertNoThrow(try safetyManager.validate(url: build))
        XCTAssertNoThrow(try safetyManager.validate(url: derived))
        XCTAssertTrue(SafetyManager.isProjectLocalBuildArtifact(build.path, home: home))
        XCTAssertFalse(SafetyManager.isProjectLocalBuildArtifact("\(home)/Documents/my_project/src", home: home))
    }

    func testShallowAbsoluteRootsRejected() {
        let shallowRoots = ["/build", "/data", "/scratch"]
        for path in shallowRoots {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "\(path) must be rejected") { error in
                XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath(path))
            }
        }
    }

    func testProtectedOptApplicationsUsersShared() {
        let protected: [(String, String)] = [
            ("\(home)/Documents", "\(home)/Documents"),
            ("\(home)/Desktop", "\(home)/Desktop"),
            ("\(home)/Downloads", "\(home)/Downloads"),
            ("\(home)/Movies", "\(home)/Movies"),
            ("\(home)/Music", "\(home)/Music"),
            ("\(home)/Pictures", "\(home)/Pictures"),
        ]
        for (path, refused) in protected {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "\(path) must be rejected") { error in
                XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath(refused))
            }
        }
    }

    func testHomebrewCellarAllowedUnderException() {
        let path = "\(home)/opt/homebrew/Cellar/python@3.14/3.14.6/IDLE 3.app"
        let url = URL(fileURLWithPath: path)
        let managerWithException = SafetyManager(
            allowedExceptions: ["\(home)/opt/homebrew/Cellar"],
            homeDirectory: home
        )
        XCTAssertNoThrow(try managerWithException.validate(url: url, policy: .uninstall))
    }

    func testIsShallowAbsoluteRoot() {
        XCTAssertTrue(SafetyManager.isShallowAbsoluteRoot("/build"))
        XCTAssertTrue(SafetyManager.isShallowAbsoluteRoot("/data"))
        XCTAssertFalse(SafetyManager.isShallowAbsoluteRoot("/"))
        XCTAssertFalse(SafetyManager.isShallowAbsoluteRoot("/opt/homebrew"))
        XCTAssertFalse(SafetyManager.isShallowAbsoluteRoot("/usr/local/bin"))
    }
}
