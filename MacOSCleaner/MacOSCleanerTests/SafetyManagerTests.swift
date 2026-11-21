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

    func testUninstallPolicyBlocksBrowserUserDataForGenericAndForeignApps() {
        let chromeRoot = "\(home)/Library/Application Support/Google/Chrome"
        let chromeDefault = "\(chromeRoot)/Default"
        let googleParent = "\(home)/Library/Application Support/Google"
        let loginData = "\(chromeDefault)/Login Data"
        let sysChrome = "/Library/Application Support/Google/Chrome"

        // Generic .uninstall (e.g. OrphanScanner) must NEVER delete browser profiles or ancestors.
        for path in [chromeRoot, chromeDefault, googleParent, sysChrome] {
            XCTAssertThrowsError(
                try safetyManager.validate(url: URL(fileURLWithPath: path), policy: .uninstall),
                "Generic .uninstall must block \(path)"
            )
        }

        // Foreign apps (Google Drive with same Team ID, Chrome Canary, Chrome PWA shim) must be blocked.
        for foreignBundleID in ["com.google.drivefs", "com.google.Chrome.canary", "com.google.Chrome.app.aghbiahbpaij"] {
            let policy = DeletionPolicy.uninstallApp(bundleID: foreignBundleID)
            for path in [chromeRoot, chromeDefault, googleParent, sysChrome] {
                XCTAssertThrowsError(
                    try safetyManager.validate(url: URL(fileURLWithPath: path), policy: policy),
                    "Uninstalling \(foreignBundleID) must not touch \(path)"
                )
            }
        }

        // Uninstalling Chrome itself may target Chrome's own user-data folder,
        // while keeping the shared Google parent, system host folder, and credentials blocked.
        let chromePolicy = DeletionPolicy.uninstallApp(bundleID: "com.google.Chrome")
        XCTAssertNoThrow(try safetyManager.validate(url: URL(fileURLWithPath: chromeRoot), policy: chromePolicy))
        XCTAssertNoThrow(try safetyManager.validate(url: URL(fileURLWithPath: chromeDefault), policy: chromePolicy))
        XCTAssertThrowsError(try safetyManager.validate(url: URL(fileURLWithPath: googleParent), policy: chromePolicy))
        XCTAssertThrowsError(try safetyManager.validate(url: URL(fileURLWithPath: sysChrome), policy: chromePolicy))
        XCTAssertThrowsError(try safetyManager.validate(url: URL(fileURLWithPath: loginData), policy: chromePolicy))
    }

    func testCleanupBlocksExtensionsAndNestedCacheFoldersInProfiles() {
        let blocked = [
            "\(home)/Library/Application Support/Google/Chrome/Default/Extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm/1.60.0_0/cache/data.bin",
            "\(home)/Library/Application Support/Google/Chrome/Default/Local Extension Settings/cjpalhdlnbpafiamejdnhcphjbkeiagm/thumbnails/icon.png",
            "\(home)/Library/Application Support/Google/Chrome/Default/Local Extension Storage/cjpalhdlnbpafiamejdnhcphjbkeiagm/cache",
            "\(home)/Library/Application Support/Google/Chrome/Default/IndexedDB/https_bank.example_0.indexeddb.leveldb/cachestorage",
            "\(home)/Library/Application Support/Google/Chrome/Default/Service Worker",
            "\(home)/Library/Application Support/Google/Chrome/Default/Service Worker/Database",
            "\(home)/Library/Application Support/Google/Chrome/Default/Session Storage",
            "\(home)/Library/Application Support/Google/Chrome/Default/Sync Data",
            "\(home)/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.bank.token.json",
            "\(home)/Library/Application Support/Google/Chrome/External Extensions/ext.json",
            "\(home)/Library/Application Support/Firefox/Profiles/abcd.default-release/storage/default/https+++bank/cache",
            "/Library/Application Support/Google/Chrome/External Extensions/ext.json",
            "/Library/Google/Chrome/NativeMessagingHosts/com.bank.token.json",
        ]
        for path in blocked {
            XCTAssertThrowsError(
                try safetyManager.validate(url: URL(fileURLWithPath: path), policy: .cleanup),
                "Cleanup must block nested/protected browser path \(path)"
            )
        }
    }

    func testBrowserProtectionIsCaseInsensitiveAndHandlesSymlinkedHome() throws {
        // Mixed/wrong casing on APFS must still be protected.
        let casedPaths = [
            "\(home)/library/application support/google/CHROME/Default/Extensions/ext/1.0/cache/file",
            "\(home)/LIBRARY/Application Support/Google/chrome/Default/Bookmarks",
            "\(home)/Library/Application Support/ARC/User Data/Default/History",
        ]
        for path in casedPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup))
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstall))
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstallApp(bundleID: "com.google.drivefs")))
        }

        // Symlinked home directory (e.g. /Users/alex -> /Volumes/Data/Users/alex)
        let parentRoot = fileSystemContext.allowedRoots[0]
        let realHome = parentRoot.appendingPathComponent("RealHome", isDirectory: true)
        let symlinkHome = parentRoot.appendingPathComponent("SymlinkHome", isDirectory: true)
        let chromeDefault = realHome.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Extensions/ext/cache", isDirectory: true)
        try FileManager.default.createDirectory(at: chromeDefault, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkHome, withDestinationURL: realHome)

        let ctx = FileSystemContext(homeDirectory: symlinkHome, allowedRoots: [parentRoot], enforceAllowedRoots: true)
        let managerReal = SafetyManager(homeDirectory: realHome.path, fileSystemContext: ctx)
        let managerSym = SafetyManager(homeDirectory: symlinkHome.path, fileSystemContext: ctx)

        let viaSym = symlinkHome.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Extensions/ext/cache")
        let viaReal = realHome.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Extensions/ext/cache")
        let viaSymRoot = symlinkHome.appendingPathComponent("Library/Application Support/Google/Chrome")

        XCTAssertThrowsError(try managerReal.validate(url: viaSym, policy: .cleanup))
        XCTAssertThrowsError(try managerSym.validate(url: viaReal, policy: .cleanup))
        XCTAssertThrowsError(try managerReal.validate(url: viaSymRoot, policy: .uninstallApp(bundleID: "com.google.drivefs")))
        XCTAssertThrowsError(try managerSym.validate(url: viaSymRoot, policy: .uninstall))
    }

    func testAllBrowserRootsProtectedAndCachesAllowed() {
        let protectedAllPolicies = [
            "\(home)/Library/Application Support/Arc/StorableSidebar.json",
            "\(home)/Library/Application Support/Orion/Defaults",
            "\(home)/Library/Application Support/DuckDuckGo/SessionData",
            "\(home)/Library/Application Support/Yandex/YandexBrowser/Default/Bookmarks",
            "\(home)/Library/Application Support/Firefox/Crash Reports",
            "\(home)/Library/Application Support/Mozilla/Firefox/Profiles/abc/cookies.sqlite",
            "\(home)/Library/Application Support/Waterfox/Profiles/abc/logins.json",
            "\(home)/Library/Application Support/LibreWolf/Profiles/abc/places.sqlite",
            "\(home)/Library/Application Support/MullvadBrowser/Profiles/abc/cookies.sqlite",
            "\(home)/Library/Application Support/TorBrowser-Data/Browser/profile.default",
            "\(home)/Library/Safari/Bookmarks.plist",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/Safari/History.db",
            "\(home)/Library/WebKit/com.apple.Safari",
        ]
        for path in protectedAllPolicies {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup), "Cleanup must block \(path)")
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstall), "Uninstall must block \(path)")
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstallApp(bundleID: "com.example.other")))
        }

        // System-protected Safari cannot be deleted even when passing Safari's bundle ID.
        XCTAssertThrowsError(try safetyManager.validate(
            url: URL(fileURLWithPath: "\(home)/Library/Safari"),
            policy: .uninstallApp(bundleID: "com.apple.Safari")
        ))

        // Narrow caches stay cleanable under .cleanup.
        let allowedCaches = [
            "\(home)/Library/Application Support/Arc/User Data/Default/Cache",
            "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Code Cache",
            "\(home)/Library/Application Support/Yandex/YandexBrowser/Default/GPUCache",
            "\(home)/Library/Safari/Favicon Cache",
        ]
        for path in allowedCaches {
            XCTAssertNoThrow(try safetyManager.validate(url: URL(fileURLWithPath: path), policy: .cleanup), "Cleanup must allow \(path)")
        }
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

    func testProjectLocalBuildArtifactUnderDocumentsAllowed() throws {
        let projectDir = URL(fileURLWithPath: "\(home)/Documents/my_project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0".write(
            to: projectDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let build = projectDir.appendingPathComponent("build")
        let derived = URL(fileURLWithPath: "\(home)/Developer/Foo/DerivedData")
        XCTAssertNoThrow(try safetyManager.validate(url: build))
        XCTAssertNoThrow(try safetyManager.validate(url: derived))
        XCTAssertTrue(SafetyManager.isProjectLocalBuildArtifact(build.path, home: home))
        XCTAssertFalse(SafetyManager.isProjectLocalBuildArtifact("\(home)/Documents/my_project/src", home: home))

        // Without sibling project marker, universal names like `build` must be rejected.
        let nonProjectBuild = URL(fileURLWithPath: "\(home)/Documents/vacation_photos/build")
        XCTAssertFalse(SafetyManager.isProjectLocalBuildArtifact(nonProjectBuild.path, home: home))
        XCTAssertThrowsError(try safetyManager.validate(url: nonProjectBuild))
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

    func testIDESettingsProtected() {
        let idePaths = [
            "\(home)/Projects/my-app/.vscode/settings.json",
            "\(home)/Projects/my-app/.vscode",
            "\(home)/Projects/my-app/.idea/workspace.xml",
            "\(home)/Projects/my-app/.idea",
            "\(home)/Library/Application Support/Code/User/settings.json",
            "\(home)/Library/Application Support/Cursor/User/keybindings.json"
        ]

        for path in idePaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Path \(path) must be protected") { error in
                guard case SafetyError.protectedPath = error else {
                    XCTFail("Expected protectedPath for \(path), got \(error)")
                    return
                }
            }
        }
    }

    func testFinderSidebarFavoritesProtected() {
        let favoritePaths = [
            "\(home)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl3",
            "\(home)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteVolumes.sfl3",
            "\(home)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ProjectsItems.sfl3"
        ]

        for path in favoritePaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url), "Path \(path) must be protected") { error in
                guard case SafetyError.protectedPath = error else {
                    XCTFail("Expected protectedPath for \(path), got \(error)")
                    return
                }
            }
        }
    }

    func testICloudDriveHardRefused() {
        let paths = [
            "\(home)/Library/Mobile Documents",
            "\(home)/Library/Mobile Documents/com~apple~CloudDocs",
            "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Documents/file.txt",
        ]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup))
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstall))
        }
    }

    func testMessagesProtected() {
        let paths = [
            "\(home)/Library/Messages",
            "\(home)/Library/Messages/chat.db",
            "\(home)/Library/Messages/chat.db-wal",
            "\(home)/Library/Messages/chat.db-shm",
            "\(home)/Library/Messages/Attachments",
        ]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup))
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstall))
        }
    }

    func testMailProtectedUnderCleanupAndAllowedBundlesUnderUninstall() {
        let mailPaths = [
            "\(home)/Library/Mail",
            "\(home)/Library/Mail/V10",
            "\(home)/Library/Mail/V10/MailData/Envelope Index",
            "\(home)/Library/Mail/V10/Attachments",
        ]
        for path in mailPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup))
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstall))
        }

        let bundlePlugin = "\(home)/Library/Mail/Bundles/SomePlugin.mailbundle"
        XCTAssertNoThrow(try safetyManager.validate(url: URL(fileURLWithPath: bundlePlugin), policy: .uninstall))
        // Still blocked under cleanup
        XCTAssertThrowsError(try safetyManager.validate(url: URL(fileURLWithPath: bundlePlugin), policy: .cleanup))
    }

    func testAppleGroupContainersProtected() {
        let appleGroupPaths = [
            "\(home)/Library/Group Containers/group.com.apple.notes",
            "\(home)/Library/Group Containers/group.com.apple.iCloudDrive",
            "\(home)/Library/Group Containers/com.apple.mail",
            "\(home)/Library/Group Containers",
        ]
        for path in appleGroupPaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup))
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .uninstall))
        }

        let thirdPartyGroup = "\(home)/Library/Group Containers/group.com.example.app"
        XCTAssertNoThrow(try safetyManager.validate(url: URL(fileURLWithPath: thirdPartyGroup), policy: .cleanup))
        XCTAssertNoThrow(try safetyManager.validate(url: URL(fileURLWithPath: thirdPartyGroup), policy: .uninstall))
    }

    func testSafariAndFirefoxCookiesProtected() {
        let cookiePaths = [
            "\(home)/Library/Cookies/Cookies.binarycookies",
            "\(home)/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
            "\(home)/Library/Application Support/Firefox/Profiles/abc.default/cookies.sqlite",
            "\(home)/Library/Application Support/Firefox/Profiles/abc.default/logins.json",
            "\(home)/Library/Application Support/Firefox/Profiles/abc.default/key4.db",
        ]
        for path in cookiePaths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup), "Cookie/credential path \(path) must be protected under cleanup")
        }
    }

    func testProjectLocalBuildArtifactRequiresDepth() throws {
        // Direct child of Documents or Desktop is NOT a project artifact
        let directDocumentsBuild = URL(fileURLWithPath: "\(home)/Documents/build")
        let directDesktopBuild = URL(fileURLWithPath: "\(home)/Desktop/build")
        let directNodeModules = URL(fileURLWithPath: "\(home)/Documents/node_modules")
        XCTAssertFalse(SafetyManager.isProjectLocalBuildArtifact(directDocumentsBuild.path, home: home))
        XCTAssertFalse(SafetyManager.isProjectLocalBuildArtifact(directDesktopBuild.path, home: home))
        XCTAssertFalse(SafetyManager.isProjectLocalBuildArtifact(directNodeModules.path, home: home))

        XCTAssertThrowsError(try safetyManager.validate(url: directDocumentsBuild))
        XCTAssertThrowsError(try safetyManager.validate(url: directDesktopBuild))
        XCTAssertThrowsError(try safetyManager.validate(url: directNodeModules))

        // Nested inside project with sibling marker is allowed
        let projectDir = URL(fileURLWithPath: "\(home)/Documents/my_project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "// swift".write(to: projectDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "{}".write(to: projectDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let projectBuild = projectDir.appendingPathComponent("build")
        let projectNodeModules = projectDir.appendingPathComponent("node_modules")
        XCTAssertTrue(SafetyManager.isProjectLocalBuildArtifact(projectBuild.path, home: home))
        XCTAssertTrue(SafetyManager.isProjectLocalBuildArtifact(projectNodeModules.path, home: home))
        XCTAssertNoThrow(try safetyManager.validate(url: projectBuild))
        XCTAssertNoThrow(try safetyManager.validate(url: projectNodeModules))
    }

    func testZedAndConfigFilesProtected() {
        let paths = [
            "\(home)/Documents/my_project/.zed/settings.json",
            "\(home)/Documents/my_project/.zed",
            "\(home)/Documents/my_project/settings.json",
            "\(home)/Documents/my_project/launch.json",
        ]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safetyManager.validate(url: url, policy: .cleanup), "Config path \(path) must be protected under cleanup")
        }
    }

    func testRefuseListRootMatchesWithoutDoubleSlash() {
        let unwhitelisted = URL(fileURLWithPath: "/some_unwhitelisted_system_root/child")
        XCTAssertThrowsError(try safetyManager.validate(url: unwhitelisted)) { error in
            XCTAssertEqual(error as? SafetyError, SafetyError.protectedPath("/"))
        }
    }

    func testSharedFileListSFL4RecentAllowedAndFavoritesProtected() {
        let allowedRecent = URL(fileURLWithPath: "\(home)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl4")
        XCTAssertNoThrow(try safetyManager.validate(url: allowedRecent))

        let protectedFav = URL(fileURLWithPath: "\(home)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4")
        XCTAssertThrowsError(try safetyManager.validate(url: protectedFav)) { error in
            guard case SafetyError.protectedPath = error else {
                XCTFail("Expected protectedPath, got \(error)")
                return
            }
            XCTAssertFalse(error.localizedDescription.contains("ошибка 0"))
            XCTAssertTrue(error.localizedDescription.contains("FavoriteItems.sfl4"))
        }
    }
}
