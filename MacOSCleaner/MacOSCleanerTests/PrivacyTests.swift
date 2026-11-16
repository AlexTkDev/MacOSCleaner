import SQLite3
import XCTest
@testable import MacOSCleaner

final class PrivacyTests: XCTestCase {

    // MARK: - 1.1 TCCService (Defensive SQLite + Validation + Verification)

    func test_tccService_readsModernAndLegacySchemasAndHandlesUnknownColumns() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TCCTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Modern schema with extra unknown column
        let modernDB = tempDir.appendingPathComponent("modern.db").path
        try createSQLiteDB(at: modernDB, sql: """
            CREATE TABLE access (
                service TEXT NOT NULL,
                client TEXT NOT NULL,
                client_type INTEGER NOT NULL,
                auth_value INTEGER NOT NULL,
                auth_reason INTEGER,
                last_modified INTEGER,
                future_unknown_col TEXT
            );
            INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.AppA', 0, 2, 1, 1700000000, 'extra');
            INSERT INTO access VALUES ('kTCCServiceUnknownFuture', 'com.example.AppA', 0, 0, NULL, NULL, 'extra2');
        """)

        let modernRes = TCCService.readDatabase(at: modernDB, scope: .user, hasFDA: true)
        XCTAssertTrue(modernRes.status.isAvailable)
        XCTAssertEqual(modernRes.entries.count, 2)
        XCTAssertEqual(modernRes.entries[0].service, .camera)
        XCTAssertEqual(modernRes.entries[0].authStatus, .allowed)
        XCTAssertTrue(modernRes.entries[0].isResettable)
        XCTAssertNotNil(modernRes.entries[0].lastModified)
        XCTAssertEqual(modernRes.entries[1].authStatus, .denied)
        XCTAssertFalse(modernRes.entries[1].isResettable)

        // Read-only URI must not leave -wal / -shm sidecars
        XCTAssertFalse(FileManager.default.fileExists(atPath: modernDB + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: modernDB + "-shm"))

        // Legacy schema (`allowed` instead of `auth_value`)
        let legacyDB = tempDir.appendingPathComponent("legacy.db").path
        try createSQLiteDB(at: legacyDB, sql: """
            CREATE TABLE access (service TEXT, client TEXT, allowed INTEGER);
            INSERT INTO access VALUES ('kTCCServiceMicrophone', 'com.example.Legacy', 1);
        """)
        let legacyRes = TCCService.readDatabase(at: legacyDB, scope: .user, hasFDA: true)
        XCTAssertTrue(legacyRes.status.isAvailable)
        XCTAssertEqual(legacyRes.entries.first?.authStatus, .allowed)

        // Missing access table -> graceful unavailable
        let emptyDB = tempDir.appendingPathComponent("empty.db").path
        try createSQLiteDB(at: emptyDB, sql: "CREATE TABLE other (id INTEGER);")
        let emptyRes = TCCService.readDatabase(at: emptyDB, scope: .user, hasFDA: true)
        XCTAssertFalse(emptyRes.status.isAvailable)
        XCTAssertTrue(emptyRes.entries.isEmpty)
    }

    func test_tccService_reportsNoDataWithoutFDA_andSipForSystemMissing() {
        let userRes = TCCService.readDatabase(at: "/nonexistent/TCC.db", scope: .user, hasFDA: false)
        XCTAssertEqual(userRes.status, .requiresFullDiskAccess)

        let sysRes = TCCService.readDatabase(at: "/nonexistent/SystemTCC.db", scope: .system, hasFDA: true)
        XCTAssertEqual(sysRes.status, .sipProtected)
    }

    func test_tccService_bundleIDValidation() {
        XCTAssertTrue(TCCService.isValidBundleID("com.apple.Safari"))
        XCTAssertTrue(TCCService.isValidBundleID("org.mozilla.firefox-1"))
        XCTAssertFalse(TCCService.isValidBundleID(""))
        XCTAssertFalse(TCCService.isValidBundleID("com.example..bad"))
        XCTAssertFalse(TCCService.isValidBundleID(".com.example"))
        XCTAssertFalse(TCCService.isValidBundleID("com.example;rm -rf /"))
        XCTAssertFalse(TCCService.isValidBundleID("/usr/bin/python3"))
    }

    func test_tccService_resetVerificationChecksReloadedDB() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TCCReset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userDB = tempDir.appendingPathComponent("user.db").path
        try createSQLiteDB(at: userDB, sql: """
            CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER, auth_value INTEGER);
            INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.CamApp', 0, 2);
        """)

        // Case 1: tccutil returns 0 but DB entry remains -> verificationFailed
        let mock = MockCommandRunner()
        mock.runHandler = { _, _ in CommandResult(stdout: "", stderr: "", exitCode: 0) }
        let service = TCCService(
            commandRunner: mock,
            userDBPath: userDB,
            systemDBPath: tempDir.appendingPathComponent("missing_sys.db").path,
            hasFullDiskAccessProvider: { true }
        )

        let snapshot = await service.loadSnapshot()
        let entry = try XCTUnwrap(snapshot.groups.first?.entries.first)
        do {
            _ = try await service.resetPermission(entry)
            XCTFail("Expected verificationFailed when row stays active")
        } catch let error as TCCResetError {
            guard case .verificationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        // Case 2: tccutil removes row -> succeeds
        mock.runHandler = { [userDB] _, _ in
            try? self.executeSQL(at: userDB, sql: "DELETE FROM access WHERE client = 'com.example.CamApp';")
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        let updated = try await service.resetPermission(entry)
        XCTAssertEqual(updated.totalEntryCount, 0)
    }

    func test_tccService_permissionSummaryReturnsSortedEntries() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TCCSummary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let userDB = tempDir.appendingPathComponent("user.db").path
        try createSQLiteDB(at: userDB, sql: """
            CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER, auth_value INTEGER);
            INSERT INTO access VALUES ('kTCCServiceMicrophone', 'com.example.App', 0, 0);
            INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.App', 0, 2);
            INSERT INTO access VALUES ('kTCCServicePhotos', 'com.other.App', 0, 2);
        """)

        let service = TCCService(
            userDBPath: userDB,
            systemDBPath: tempDir.appendingPathComponent("missing_sys.db").path,
            hasFullDiskAccessProvider: { true }
        )
        let summary = await service.permissionSummary(forBundleID: "com.example.App")
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.allowedCount, 1)
        XCTAssertEqual(summary.deniedCount, 1)
        XCTAssertEqual(summary.entries.first?.service, .camera)
        XCTAssertEqual(summary.entries.last?.service, .microphone)
        XCTAssertFalse(summary.requiresFDA)
    }

    // MARK: - 1.2 NetworkSnapshotService Static Profile

    func test_networkSnapshot_inspectsStaticProfileFromAppBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NetStatic-\(UUID().uuidString)", isDirectory: true)
        let appURL = tempDir.appendingPathComponent("DemoNet.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let xpcURL = contentsURL.appendingPathComponent("XPCServices/com.example.helper.xpc", isDirectory: true)
        try FileManager.default.createDirectory(at: xpcURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.DemoNet",
            "NSAppTransportSecurity": [
                "NSAllowsArbitraryLoads": true,
                "NSExceptionDomains": ["internal.example.local": ["NSExceptionAllowsInsecureHTTPLoads": true]]
            ],
            "CFBundleURLTypes": [
                ["CFBundleURLSchemes": ["demonet", "demonet-auth"]]
            ]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let profile = try XCTUnwrap(NetworkSnapshotService.inspectStaticProfile(at: appURL))
        XCTAssertTrue(profile.atsAllowsArbitraryLoads)
        XCTAssertEqual(profile.atsExceptionDomains, ["internal.example.local"])
        XCTAssertEqual(profile.urlSchemes, ["demonet", "demonet-auth"])
        XCTAssertEqual(profile.helperServices, ["com.example.helper.xpc"])
    }

    // MARK: - 1.3 BrowserExtensionScanner & LaunchPlan

    func test_browserExtensionScanner_parsesChromiumFirefoxAndLaunchPlans() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ExtTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Chromium fixture with __MSG_name__ and store update_url
        let chromeUserData = tempDir.appendingPathComponent("Chrome", isDirectory: true)
        let extVersionDir = chromeUserData.appendingPathComponent("Profile 1/Extensions/abcdefghijklmnop/1.2.3", isDirectory: true)
        let localesDir = extVersionDir.appendingPathComponent("_locales/en", isDirectory: true)
        try FileManager.default.createDirectory(at: localesDir, withIntermediateDirectories: true)

        try #"{"appName": {"message": "Sample Guard"}}"#.write(
            to: localesDir.appendingPathComponent("messages.json"),
            atomically: true,
            encoding: .utf8
        )
        let manifest = """
        {
          "name": "__MSG_APPNAME__",
          "version": "1.2.3",
          "update_url": "https://clients2.google.com/service/update2/crx",
          "permissions": ["cookies", "tabs"],
          "host_permissions": ["<all_urls>"]
        }
        """
        try manifest.write(
            to: extVersionDir.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let chromeItems = BrowserExtensionScanner.scanChromiumDirectory(userDataDir: chromeUserData, browser: .chrome)
        XCTAssertEqual(chromeItems.count, 1)
        let chromeExt = try XCTUnwrap(chromeItems.first)
        XCTAssertEqual(chromeExt.name, "Sample Guard")
        XCTAssertEqual(chromeExt.source, .store)
        XCTAssertEqual(chromeExt.risk, .high)
        XCTAssertTrue(chromeExt.highRiskPermissions.contains("cookies"))
        XCTAssertTrue(chromeExt.highRiskPermissions.contains("<all_urls>"))

        let chromePlan = BrowserExtensionScanner.launchPlan(for: chromeExt)
        XCTAssertEqual(chromePlan.browserBundleID, "com.google.Chrome")
        XCTAssertTrue(chromePlan.requiresNewInstance)
        XCTAssertEqual(chromePlan.arguments, ["--profile-directory=Profile 1", "chrome://extensions/?id=abcdefghijklmnop"])

        // Firefox fixture
        let ffProfile = tempDir.appendingPathComponent("Firefox/Profiles/abc.default", isDirectory: true)
        try FileManager.default.createDirectory(at: ffProfile, withIntermediateDirectories: true)
        let ffJSON = """
        {
          "addons": [
            {
              "id": "ext@example.org",
              "type": "extension",
              "location": "app-profile",
              "active": true,
              "version": "2.0",
              "sourceURI": "https://addons.mozilla.org/firefox/downloads/file/123/ext.xpi",
              "defaultLocale": {"name": "FF Tool"},
              "userPermissions": {"permissions": ["storage"], "origins": []}
            }
          ]
        }
        """
        try ffJSON.write(to: ffProfile.appendingPathComponent("extensions.json"), atomically: true, encoding: .utf8)

        let ffItems = BrowserExtensionScanner.scanFirefoxProfiles(at: tempDir.appendingPathComponent("Firefox/Profiles"))
        XCTAssertEqual(ffItems.count, 1)
        XCTAssertEqual(ffItems[0].source, .store)
        XCTAssertEqual(ffItems[0].risk, .normal)
        XCTAssertEqual(BrowserExtensionScanner.launchPlan(for: ffItems[0]).arguments, ["about:addons"])
    }

    // MARK: - SQLite Helpers

    private func createSQLiteDB(at path: String, sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try executeSQL(db: db, sql: sql)
    }

    private func executeSQL(at path: String, sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try executeSQL(db: db, sql: sql)
    }

    private func executeSQL(db: OpaquePointer?, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "SQLite error \(rc)"
            sqlite3_free(errMsg)
            throw NSError(domain: "PrivacyTests", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
