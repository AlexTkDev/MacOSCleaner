import XCTest
@testable import MacOSCleaner

final class CandidateCollectorTests: XCTestCase {
    private var fileSystemContext: FileSystemContext!
    private var home: String = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        home = fileSystemContext.homePath
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        home = ""
        try super.tearDownWithError()
    }

    private func makeCollector(
        commandRunner: MockCommandRunner = MockCommandRunner(),
        homebrewCellarDirectories: [URL] = [],
        darwinCacheDirectory: URL? = nil
    ) -> CandidateCollector {
        commandRunner.runDelay = .zero
        return CandidateCollector(
            commandRunner: commandRunner,
            homebrewCellarDirectories: homebrewCellarDirectories,
            darwinCacheDirectory: darwinCacheDirectory,
            fileSystemContext: fileSystemContext
        )
    }

    func test_collect_findsAppSupportDirByExactName() async throws {
        let appName = "CollectorTestApp_\(UUID().uuidString.prefix(8))"
        let fixture = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/\(appName)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let collector = makeCollector()
        let identity = AppIdentity(
            bundleID: "com.test.\(appName)",
            appName: String(appName),
            bundleName: nil,
            bundleVersion: nil,
            executableName: String(appName),
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(appName).app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["TestVendor"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        let fixturePath = fixture.resolvingSymlinksInPath().path
        XCTAssertTrue(candidates.contains { $0.resolvingSymlinksInPath().path == fixturePath }, "Collector must find Application Support dir by exact name")
    }

    func test_collect_safeMode_findsExactMatches() async throws {
        let appName = "CollectorSafeApp_\(UUID().uuidString.prefix(8))"
        let bundleID = "com.test.\(appName)"
        let fixture = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Caches/\(bundleID)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let collector = makeCollector()
        let identity = AppIdentity(
            bundleID: bundleID,
            appName: String(appName),
            bundleName: nil,
            bundleVersion: nil,
            executableName: String(appName),
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(appName).app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity, mode: .safe)
        let fixturePath = fixture.resolvingSymlinksInPath().path
        XCTAssertTrue(candidates.contains { $0.resolvingSymlinksInPath().path == fixturePath }, "Safe mode must find cache dir by exact bundle ID")
    }

    func test_collect_findsNestedCacheByTokenPrefix() async throws {
        let appName = "OpenCode"
        let nested = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Caches/com.other.updater/UpdaterCache/opencode-desktop_br")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.other.updater")) }

        let collector = makeCollector()
        let identity = AppIdentity(
            bundleID: "dev.opencode.desktop",
            appName: appName,
            bundleName: nil,
            bundleVersion: nil,
            executableName: appName,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/OpenCode.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["opencode"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertTrue(candidates.contains { $0.resolvingSymlinksInPath().path == nested.resolvingSymlinksInPath().path })
    }

    func test_collect_skipsGenericBundleTailOutsideVendorContext() async throws {
        let marker = "TailFP\(UUID().uuidString.prefix(8))"
        let root = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/\(marker)")
        // ai.<x>.desktop must not claim a folder named "desktop" outside vendor context
        let trap = root.appendingPathComponent("Data/desktop")
        try FileManager.default.createDirectory(at: trap, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let collector = makeCollector()
        let identity = AppIdentity(
            bundleID: "ai.\(marker.lowercased()).desktop",
            appName: "\(marker)App",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "\(marker)App",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(marker)App.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [marker.lowercased()],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertFalse(candidates.contains { $0.path == trap.path },
                       "Generic bundle-ID tail must not match folders outside a vendor dir")
    }

    func test_collect_findsGroupContainerFromEntitlements() async throws {
        let marker = "grp\(UUID().uuidString.prefix(8).lowercased())"
        let groupName = "FAKETEAM99.com.\(marker).shared"
        let fixture = URL(fileURLWithPath: home).appendingPathComponent("Library/Group Containers/\(groupName)")
        do {
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        } catch {
            throw XCTSkip("Cannot create Group Containers fixture (TCC/sandbox): \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: fixture) }

        let collector = makeCollector()
        // No teamID, no name relation — only the entitlements declare the group
        var identity = AppIdentity(
            bundleID: "com.other.\(marker)vpn",
            appName: "Grp\(marker)",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Grp\(marker)",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Grp\(marker).app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        identity.appGroups = [groupName]
        let candidates = await collector.collect(identity: identity)
        XCTAssertTrue(candidates.contains { $0.resolvingSymlinksInPath().path == fixture.resolvingSymlinksInPath().path },
                      "Group container declared in entitlements must be collected")
    }

    func test_collect_findsGoogleChromeVendorPath() async throws {
        let googleRoot = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Google")
        let chromeDir = googleRoot.appendingPathComponent("Chrome")
        try FileManager.default.createDirectory(at: chromeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: googleRoot) }

        let collector = makeCollector()
        let identity = AppIdentity(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            bundleName: "Chrome",
            bundleVersion: nil,
            executableName: "Google Chrome",
            teamID: "EQHXZ8M8AV",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Google", "Chrome"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertTrue(candidates.contains { $0.path == chromeDir.path })
    }

    func test_collect_marksAppsFromSameHomebrewFormulaAsReceiptPaths() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CandidateCollectorTests-\(UUID().uuidString)", isDirectory: true)
        let cellar = root.appendingPathComponent("Cellar", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func makeKeg(formula: String, version: String) throws -> [URL] {
            let keg = cellar.appendingPathComponent("\(formula)/\(version)", isDirectory: true)
            let idle = keg.appendingPathComponent("IDLE 3.app", isDirectory: true)
            let launcher = keg.appendingPathComponent("Python Launcher 3.app", isDirectory: true)
            for (app, bundleID) in [
                (idle, "org.python.IDLE"),
                (launcher, "org.python.PythonLauncher"),
            ] {
                let contents = app.appendingPathComponent("Contents", isDirectory: true)
                try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
                let plist: [String: Any] = [
                    "CFBundleIdentifier": bundleID,
                    "CFBundleName": app.deletingPathExtension().lastPathComponent,
                    "CFBundleExecutable": app.deletingPathExtension().lastPathComponent,
                ]
                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist,
                    format: .xml,
                    options: 0
                )
                try data.write(to: contents.appendingPathComponent("Info.plist"))
            }
            try Data("{}".utf8).write(to: keg.appendingPathComponent("INSTALL_RECEIPT.json"))
            return [idle, launcher]
        }

        let oldApps = try makeKeg(formula: "python@3.12", version: "3.12.13_4")
        let currentApps = try makeKeg(formula: "python@3.14", version: "3.14.6")
        // Unrelated formula must not reuse org.python.IDLE — use a distinct helper.
        let unrelatedRoot = cellar.appendingPathComponent("ruby@3.4/3.4.1/IDLE 3.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelatedRoot, withIntermediateDirectories: true)
        let unrelatedPlist: [String: Any] = [
            "CFBundleIdentifier": "org.ruby.IDLE",
            "CFBundleName": "IDLE 3",
            "CFBundleExecutable": "IDLE 3",
        ]
        try PropertyListSerialization.data(fromPropertyList: unrelatedPlist, format: .xml, options: 0)
            .write(to: unrelatedRoot.appendingPathComponent("Info.plist"))
        let unrelatedApps = [unrelatedRoot.deletingLastPathComponent()]
        let identity = AppIdentity(
            bundleID: "org.python.IDLE",
            appName: "IDLE 3",
            bundleName: "IDLE",
            bundleVersion: "3.14.6",
            executableName: "IDLE",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: currentApps[0],
            isAppStore: false, isSandboxed: false, isAdHocSigned: true,
            vendorNames: ["python"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let runner = MockCommandRunner()
        runner.runDelay = .zero
        let collection = await makeCollector(
            commandRunner: runner,
            homebrewCellarDirectories: [cellar]
        ).collectDetailed(identity: identity, mode: .safe)

        let expectedPaths = Set([oldApps[0], currentApps[0]].map {
            $0.resolvingSymlinksInPath().path
        })
        // Sibling Homebrew versions are candidates (deep scan preselects for uninstall).
        XCTAssertTrue(collection.receiptPaths.isEmpty)
        XCTAssertTrue(expectedPaths.isSubset(of: Set(
            collection.candidates.map { $0.resolvingSymlinksInPath().path }
        )))
        let unrelatedPaths = Set(unrelatedApps.map { $0.resolvingSymlinksInPath().path })
        XCTAssertTrue(unrelatedPaths.isDisjoint(with: Set(
            collection.candidates.map { $0.resolvingSymlinksInPath().path }
        )))
        let launcherPaths = Set([oldApps[1], currentApps[1]].map {
            $0.resolvingSymlinksInPath().path
        })
        XCTAssertTrue(launcherPaths.isDisjoint(with: Set(
            collection.candidates.map { $0.resolvingSymlinksInPath().path }
        )))
    }

    func test_collect_findsOnlyExactBundleFamilyInDarwinCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CandidateCollectorDarwinCache-\(UUID().uuidString)", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("C", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let marker = UUID().uuidString.lowercased()
        let bundleID = "com.example.\(marker)"
        let ownCache = cacheRoot.appendingPathComponent("\(bundleID).helper", isDirectory: true)
        let foreignCache = cacheRoot.appendingPathComponent("com.example.other.helper", isDirectory: true)
        try FileManager.default.createDirectory(at: ownCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: foreignCache, withIntermediateDirectories: true)

        let identity = AppIdentity(
            bundleID: bundleID,
            appName: "DarwinCacheTest",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "DarwinCacheTest",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/DarwinCacheTest.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let runner = MockCommandRunner()
        runner.runDelay = .zero
        let candidates = await makeCollector(
            commandRunner: runner,
            homebrewCellarDirectories: [],
            darwinCacheDirectory: cacheRoot
        ).collect(identity: identity, mode: .safe)

        let ownPath = ownCache.resolvingSymlinksInPath().path
        let foreignPath = foreignCache.resolvingSymlinksInPath().path
        XCTAssertTrue(candidates.contains { $0.resolvingSymlinksInPath().path == ownPath })
        XCTAssertFalse(candidates.contains { $0.resolvingSymlinksInPath().path == foreignPath })
    }

    func test_collect_registrySeparatesSharedAndAdminPaths() async throws {
        try CatalogTestSupport.requirePrivateCatalog()
        let chromeCache = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.google.Chrome")
        let googleUpdater = URL(fileURLWithPath: home).appendingPathComponent("Library/Google/GoogleSoftwareUpdate")
        try FileManager.default.createDirectory(at: chromeCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: googleUpdater, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: home).appendingPathComponent("Library")) }

        let collection = await makeCollector().collectDetailed(
            identity: AppIdentity(
                bundleID: "com.google.Chrome",
                appName: "Google Chrome",
                bundleName: "Chrome",
                bundleVersion: nil,
                executableName: "Google Chrome",
                teamID: nil,
                signingAuthority: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
                isAppStore: false, isSandboxed: false, isAdHocSigned: false,
                vendorNames: ["Google", "Chrome"],
                helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
                isElectron: false, isJetBrains: false, isFlutter: false,
                isJava: false, isQt: false, isDocker: false
            ),
            mode: .safe
        )

        XCTAssertTrue(collection.candidates.contains { $0.path == chromeCache.path })
        XCTAssertTrue(collection.catalogPaths.contains { $0.path == chromeCache.path })
        XCTAssertTrue(collection.sharedPaths.contains { $0.path == googleUpdater.path })

        for path in collection.catalogPaths {
            let lower = path.path.lowercased()
            XCTAssertFalse(lower.contains("googlesoftwareupdate"), "Shared updater must not inflate catalog confidence")
            XCTAssertFalse(lower.contains("keystone"), "Shared Keystone must not inflate catalog confidence")
        }
        XCTAssertTrue(collection.sharedPaths.isDisjoint(with: collection.catalogPaths))
        for shared in collection.sharedPaths {
            XCTAssertFalse(
                collection.catalogPaths.contains(shared),
                "Shared component \(shared.path) must not appear in catalogPaths"
            )
        }

        let chromeRegistry = GeneratedCleanupPaths.appPaths(forBundleID: "com.google.Chrome")
        XCTAssertNotNil(chromeRegistry)
        if let chromeRegistry {
            let adminTemplates = chromeRegistry.paths.filter(\.requiresAdmin)
            XCTAssertFalse(adminTemplates.isEmpty)
            for entry in adminTemplates {
                let resolved = PathToken.home.resolveTemplate(entry.template, home: home)
                XCTAssertFalse(collection.catalogPaths.contains(URL(fileURLWithPath: resolved).standardizedFileURL))
            }
        }
    }

    func test_collect_catalogPathsExcludeAppData() async throws {
        try CatalogTestSupport.requirePrivateCatalog()
        let appSupport = "\(home)/Library/Application Support/Google/Chrome"
        try FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: "\(home)/Library") }

        let collection = await makeCollector().collectDetailed(
            identity: AppIdentity(
                bundleID: "com.google.Chrome",
                appName: "Google Chrome",
                bundleName: "Chrome",
                bundleVersion: nil,
                executableName: "Google Chrome",
                teamID: nil,
                signingAuthority: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
                isAppStore: false, isSandboxed: false, isAdHocSigned: false,
                vendorNames: ["Google", "Chrome"],
                helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
                isElectron: false, isJetBrains: false, isFlutter: false,
                isJava: false, isQt: false, isDocker: false
            ),
            mode: .safe
        )

        XCTAssertTrue(collection.candidates.contains { $0.path == appSupport })
        XCTAssertFalse(collection.catalogPaths.contains { $0.path == appSupport })
    }

    func test_collect_doesNotCrossSelectSiblingOfficeAndAdobeApps() async throws {
        try CatalogTestSupport.requirePrivateCatalog()
        let microsoft = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Microsoft Office")
        let wordCache = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.microsoft.word")
        let excelCache = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.microsoft.excel")
        let adobeRoot = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Adobe")
        let photoshopCache = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.adobe.Photoshop")
        let illustratorCache = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.adobe.Illustrator")

        for path in [microsoft, wordCache, excelCache, adobeRoot, photoshopCache, illustratorCache] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: home).appendingPathComponent("Library")) }

        let collector = makeCollector()

        let wordCollection = await collector.collectDetailed(
            identity: AppIdentity(
                bundleID: "com.microsoft.word",
                appName: "Microsoft Word",
                bundleName: "Word",
                bundleVersion: nil,
                executableName: "Microsoft Word",
                teamID: "UBF8T346G9",
                signingAuthority: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Microsoft Word.app"),
                isAppStore: false, isSandboxed: false, isAdHocSigned: false,
                vendorNames: ["Microsoft", "Office"],
                helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
                isElectron: false, isJetBrains: false, isFlutter: false,
                isJava: false, isQt: false, isDocker: false
            ),
            mode: .safe
        )

        XCTAssertTrue(wordCollection.candidates.contains { $0.resolvingSymlinksInPath().path == wordCache.resolvingSymlinksInPath().path })
        XCTAssertTrue(wordCollection.sharedPaths.contains { $0.resolvingSymlinksInPath().path == microsoft.resolvingSymlinksInPath().path })
        XCTAssertFalse(wordCollection.candidates.contains { $0.resolvingSymlinksInPath().path == microsoft.resolvingSymlinksInPath().path })
        XCTAssertFalse(wordCollection.candidates.contains { $0.resolvingSymlinksInPath().path == excelCache.resolvingSymlinksInPath().path })

        let photoshopCollection = await collector.collectDetailed(
            identity: AppIdentity(
                bundleID: "com.adobe.Photoshop",
                appName: "Adobe Photoshop",
                bundleName: "Photoshop",
                bundleVersion: nil,
                executableName: "Adobe Photoshop",
                teamID: "JQ525L2MZD",
                signingAuthority: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Adobe Photoshop 2026.app"),
                isAppStore: false, isSandboxed: false, isAdHocSigned: false,
                vendorNames: ["Adobe"],
                helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
                isElectron: false, isJetBrains: false, isFlutter: false,
                isJava: false, isQt: false, isDocker: false
            ),
            mode: .safe
        )

        // Adobe shared vendor root shown informationally, not as a Photoshop-only sharedPaths claim.
        XCTAssertTrue(photoshopCollection.candidates.contains { $0.resolvingSymlinksInPath().path == photoshopCache.resolvingSymlinksInPath().path })
        XCTAssertFalse(photoshopCollection.candidates.contains { $0.resolvingSymlinksInPath().path == adobeRoot.resolvingSymlinksInPath().path })
        XCTAssertFalse(photoshopCollection.candidates.contains { $0.resolvingSymlinksInPath().path == illustratorCache.resolvingSymlinksInPath().path })
    }

    func test_collect_safariRegistryExcluded() async {
        let collection = await makeCollector().collectDetailed(
            identity: AppIdentity(
                bundleID: "com.apple.Safari",
                appName: "Safari",
                bundleName: "Safari",
                bundleVersion: nil,
                executableName: "Safari",
                teamID: nil,
                signingAuthority: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                isAppStore: false, isSandboxed: false, isAdHocSigned: false,
                vendorNames: [],
                helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
                isElectron: false, isJetBrains: false, isFlutter: false,
                isJava: false, isQt: false, isDocker: false
            ),
            mode: .safe
        )
        XCTAssertTrue(collection.catalogPaths.isEmpty)
        XCTAssertTrue(collection.sharedPaths.isEmpty)
    }

    func test_collect_androidStudioAddsHomeToolingPaths() async throws {
        let gradle = URL(fileURLWithPath: home).appendingPathComponent(".gradle")
        let androidHome = URL(fileURLWithPath: home).appendingPathComponent(".android")
        let androidLib = URL(fileURLWithPath: home).appendingPathComponent("Library/Android")
        try FileManager.default.createDirectory(at: gradle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: androidHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: androidLib, withIntermediateDirectories: true)

        let collector = makeCollector()
        let identity = AppIdentity(
            bundleID: "com.google.android.studio",
            appName: "Android Studio",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "studio",
            teamID: "EQHXZ8M8AV",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Android Studio.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Google"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: true, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        let paths = Set(candidates.map { $0.resolvingSymlinksInPath().path })
        XCTAssertTrue(paths.contains(gradle.resolvingSymlinksInPath().path))
        XCTAssertTrue(paths.contains(androidHome.resolvingSymlinksInPath().path))
        XCTAssertTrue(paths.contains(androidLib.resolvingSymlinksInPath().path))
    }
}
