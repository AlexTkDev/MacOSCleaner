import XCTest
@testable import MacOSCleaner

final class UninstallerServiceTests: XCTestCase {
    var service: UninstallerService!

    override func setUp() async throws {
        service = UninstallerService()
    }

    func testScanState_initiallyDiscovered() {
        let app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp"
        )
        XCTAssertEqual(app.scanState, .discovered)
    }

    func testAppInfo_totalSize_withRelatedFiles() {
        var app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp",
            size: 100
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Caches/test.cache"), size: 50),
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Preferences/test.plist"), size: 30),
        ]
        XCTAssertEqual(app.totalSize, 180)
    }

    func testAppInfo_totalSize_ignoresDeselected() {
        var app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp",
            size: 100
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Caches/test.cache"), isSelected: false, size: 50),
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Preferences/test.plist"), size: 30),
        ]
        XCTAssertEqual(app.totalSize, 130)
    }

    func testConfidenceTier_comparable() {
        XCTAssertTrue(ConfidenceTier.possible < ConfidenceTier.veryLikely)
        XCTAssertTrue(ConfidenceTier.veryLikely < ConfidenceTier.guaranteed)
        XCTAssertTrue(ConfidenceTier.ignore < ConfidenceTier.possible)
    }

    func testRelatedFile_evidenceAndConfidence() {
        let file = UninstallerService.RelatedFile(
            url: URL(fileURLWithPath: "/Library/Caches/test.cache"),
            evidence: [.bundleIDExact, .teamID],
            confidence: .guaranteed
        )
        XCTAssertTrue(file.evidence.contains(.bundleIDExact))
        XCTAssertEqual(file.confidence, .guaranteed)
    }

    func testProtectedMailPaths() {
        let home = "/Users/test-fixture-home"
        XCTAssertTrue(UninstallerService.isProtectedMailPath("\(home)/Library/Mail", homeDirectory: home))
        XCTAssertTrue(UninstallerService.isProtectedMailPath("\(home)/Library/Mail/V10/INBOX.mbox", homeDirectory: home))
        XCTAssertTrue(UninstallerService.isProtectedMailPath("\(home)/Library/Containers/com.apple.mail/Data", homeDirectory: home))
        // Mail plugins are legitimate residuals
        XCTAssertFalse(UninstallerService.isProtectedMailPath("\(home)/Library/Mail/Bundles/SomePlugin.mailbundle", homeDirectory: home))
        XCTAssertFalse(UninstallerService.isProtectedMailPath("\(home)/Library/Application Support/SomeApp", homeDirectory: home))
    }

    func testPhysicalSize_sparseFile_reportsAllocatedNotLogical() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparseSizeTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1 GB logical, ~0 allocated (APFS sparse file, like OrbStack data.img.raw)
        let sparse = dir.appendingPathComponent("data.img.raw")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 1_073_741_824)
        try handle.close()

        let logical = (try? sparse.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        XCTAssertEqual(logical, 1_073_741_824)

        let physical = FileManager.default.getPhysicalDirectorySize(url: dir, excludedPaths: [])
        XCTAssertLessThan(physical, 50 * 1024 * 1024,
                          "Sparse file must be counted by allocated size, got \(physical)")

        let filePhysical = FileManager.default.getPhysicalDirectorySize(url: sparse, excludedPaths: [])
        XCTAssertLessThan(filePhysical, 50 * 1024 * 1024)
    }

    func testEvidence_category_mapping() {
        XCTAssertEqual(Evidence.bundleIDExact.category, .identity)
        XCTAssertEqual(Evidence.teamID.category, .signature)
        XCTAssertEqual(Evidence.launchAgent.category, .system)
        XCTAssertEqual(Evidence.packageReceipt.category, .metadata)
        XCTAssertEqual(Evidence.spotlight.category, .content)
        XCTAssertEqual(Evidence.parentDirectory.category, .graph)
        XCTAssertEqual(Evidence.launchServicesRegistered.category, .launchServices)
    }

    func testGroupKey_andMultiVersionAppInfo() {
        let app1 = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/opt/homebrew/Cellar/python@3.14/3.14.6/IDLE 3.app"),
            bundleID: "org.python.IDLE",
            name: "IDLE 3",
            size: 200,
            version: "3.14.6"
        )
        let app2 = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/opt/homebrew/Cellar/python@3.12/3.12.13/IDLE 3.app"),
            bundleID: "org.python.IDLE",
            name: "IDLE 3",
            size: 150,
            version: "3.12.13"
        )

        XCTAssertEqual(UninstallerService.groupKey(for: app1), UninstallerService.groupKey(for: app2))

        let grouped = UninstallerService.AppInfo(
            url: app1.url,
            bundleID: app1.bundleID,
            name: app1.name,
            size: 350,
            version: "3.14.6, 3.12.13",
            versions: [app1, app2]
        )

        XCTAssertTrue(grouped.isGrouped)
        XCTAssertEqual(grouped.versions.count, 2)
        XCTAssertEqual(grouped.totalSize, 350)
    }

    // MARK: - Trash & Bypass Trash Behavior

    func testUninstall_bypassTrash_deletesDirectly_preservesThirdPartyTrash() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer {
            if let root = ctx.allowedRoots.first {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trashDir = ctx.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let testService = UninstallerService(safetyManager: safety, trashManager: trash)

        // Setup app & related files
        let appDir = ctx.homeDirectory.appendingPathComponent("Applications/Demo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appBinary = appDir.appendingPathComponent("Demo")
        try "binary".data(using: .utf8)!.write(to: appBinary)

        let cacheDir = ctx.homeDirectory.appendingPathComponent("Library/Caches/com.demo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent("cache.db")
        try "cache".data(using: .utf8)!.write(to: cacheFile)

        // Setup third-party file in trash
        let finderTrashFile = trashDir.appendingPathComponent("user_important_doc.pdf")
        try "important".data(using: .utf8)!.write(to: finderTrashFile)

        var app = UninstallerService.AppInfo(
            url: appDir,
            bundleID: "com.demo.app",
            name: "Demo"
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: cacheFile, isSelected: true, size: 5)
        ]

        _ = try await testService.uninstall(app: app, bypassTrash: true, emptyTrashImmediately: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: appDir.path), "App should be removed directly")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path), "Related file should be removed directly")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderTrashFile.path), "Finder trash files must never be touched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("Demo.app").path), "Should not be moved to trash")
    }

    func testUninstall_emptyTrashImmediately_deletesOwnFiles_preservesThirdPartyTrash() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer {
            if let root = ctx.allowedRoots.first {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trashDir = ctx.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let testService = UninstallerService(safetyManager: safety, trashManager: trash)

        let appDir = ctx.homeDirectory.appendingPathComponent("Applications/Demo2.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appBinary = appDir.appendingPathComponent("Demo2")
        try "binary".data(using: .utf8)!.write(to: appBinary)

        let finderTrashFile = trashDir.appendingPathComponent("existing_trash_file.txt")
        try "dont_delete_me".data(using: .utf8)!.write(to: finderTrashFile)

        let app = UninstallerService.AppInfo(
            url: appDir,
            bundleID: "com.demo2.app",
            name: "Demo2"
        )

        _ = try await testService.uninstall(app: app, bypassTrash: false, emptyTrashImmediately: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: appDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("Demo2.app").path),
                       "App should be removed immediately from Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderTrashFile.path),
                      "Finder trash files must never be touched by emptyTrashImmediately")
    }

    func testUninstall_defaultTrash_movesToTrash_preservesThirdPartyTrash() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer {
            if let root = ctx.allowedRoots.first {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trashDir = ctx.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let testService = UninstallerService(safetyManager: safety, trashManager: trash)

        let appDir = ctx.homeDirectory.appendingPathComponent("Applications/Demo3.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appBinary = appDir.appendingPathComponent("Demo3")
        try "binary".data(using: .utf8)!.write(to: appBinary)

        let finderTrashFile = trashDir.appendingPathComponent("existing_trash_file.txt")
        try "dont_delete_me".data(using: .utf8)!.write(to: finderTrashFile)

        let app = UninstallerService.AppInfo(
            url: appDir,
            bundleID: "com.demo3.app",
            name: "Demo3"
        )

        _ = try await testService.uninstall(app: app, bypassTrash: false, emptyTrashImmediately: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: appDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDir.appendingPathComponent("Demo3.app").path),
                      "App should remain in Trash when emptyTrashImmediately is false")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderTrashFile.path),
                      "Finder trash files must never be touched")
    }

    func testIsApplicationConfigurationPath() {
        XCTAssertTrue(UninstallerService.isApplicationConfigurationPath("/Users/alex/Library/Preferences/com.example.app.plist"))
        XCTAssertTrue(UninstallerService.isApplicationConfigurationPath("/Users/alex/.config/nvim/init.vim"))
        XCTAssertTrue(UninstallerService.isApplicationConfigurationPath("/Users/alex/Library/Application Support/JetBrains/IntelliJIdea2024.1/options/other.xml"))
        XCTAssertTrue(UninstallerService.isApplicationConfigurationPath("/Users/alex/Library/Application Support/Code/User/settings.json"))
        XCTAssertTrue(UninstallerService.isApplicationConfigurationPath("/Users/alex/Library/Application Support/Cursor/User/settings.json"))
        // Caches and logs are NOT configurations
        XCTAssertFalse(UninstallerService.isApplicationConfigurationPath("/Users/alex/Library/Caches/com.example.app"))
        XCTAssertFalse(UninstallerService.isApplicationConfigurationPath("/Users/alex/Library/Logs/com.example.app.log"))
    }

    func testRemoveOrphanedResiduals_returnsStructuredResult() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer {
            if let root = ctx.allowedRoots.first {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let safety = SafetyManager(homeDirectory: ctx.homePath, fileSystemContext: ctx)
        let trashDir = ctx.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let testService = UninstallerService(safetyManager: safety, trashManager: trash)

        let orphanFile = ctx.homeDirectory.appendingPathComponent("Library/Caches/orphan.cache")
        try FileManager.default.createDirectory(at: orphanFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "orphan_data".data(using: .utf8)!.write(to: orphanFile)

        let orphanItem = OrphanItem(
            url: orphanFile,
            name: "Orphan",
            bundleID: "com.example.orphan",
            sizeBytes: 11,
            category: "Caches",
            isSelected: true
        )

        let result = try await testService.removeOrphanedResiduals([orphanItem], bypassTrash: false)
        XCTAssertEqual(result.succeededItems.count, 1)
        XCTAssertEqual(result.failedItems.count, 0)
        XCTAssertEqual(result.freed, 11)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanFile.path))
    }

    func testAppNameMatchesFileName_twoLetterNames() {
        // VLC (3 chars)
        let vlcMatch = EvidenceProbe.appNameMatchesFileName("VLC", appName: "VLC")
        XCTAssertTrue(vlcMatch.exact)

        // Arc (3 chars)
        let arcMatch = EvidenceProbe.appNameMatchesFileName("Arc", appName: "Arc")
        XCTAssertTrue(arcMatch.exact)

        // Go (2 chars)
        let goMatch = EvidenceProbe.appNameMatchesFileName("Go", appName: "Go")
        XCTAssertTrue(goMatch.exact)

        // Zed (3 chars)
        let zedMatch = EvidenceProbe.appNameMatchesFileName("zed", appName: "Zed")
        XCTAssertTrue(zedMatch.exact)

        // 1 char name like "R" should NOT match via appNameMatchesFileName
        let rMatch = EvidenceProbe.appNameMatchesFileName("R", appName: "R")
        XCTAssertFalse(rMatch.exact)
    }

    func testIsCLIConfigPath_detectsProtectedTools() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cursorConfig = URL(fileURLWithPath: "\(home)/.config/cursor")
        let claudeConfig = URL(fileURLWithPath: "\(home)/.config/claude")
        let openCodeLocal = URL(fileURLWithPath: "\(home)/.local/share/opencode")
        let regularConfig = URL(fileURLWithPath: "\(home)/.config/myapp_unique_123")
        let randomFile = URL(fileURLWithPath: "/Library/Caches/cursor")

        XCTAssertTrue(UninstallerService.isCLIConfigPath(cursorConfig))
        XCTAssertTrue(UninstallerService.isCLIConfigPath(claudeConfig))
        XCTAssertTrue(UninstallerService.isCLIConfigPath(openCodeLocal))
        XCTAssertFalse(UninstallerService.isCLIConfigPath(regularConfig))
        XCTAssertFalse(UninstallerService.isCLIConfigPath(randomFile))
    }

    func testAppInfo_isIntelOnlyDefaultFalse() {
        let app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp"
        )
        XCTAssertFalse(app.isIntelOnly)
    }

    func testDeepScan_chromeProfileNeverPreselectedAndDriveDoesNotTouchChrome() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }

        let appsDir = ctx.homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        let chromeApp = appsDir.appendingPathComponent("Google Chrome.app", isDirectory: true)
        let driveApp = appsDir.appendingPathComponent("Google Drive.app", isDirectory: true)
        let chromeProfile = ctx.homeDirectory.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        let chromeDefault = chromeProfile.appendingPathComponent("Default/Extensions/ext1", isDirectory: true)
        let chromeCache = ctx.homeDirectory.appendingPathComponent("Library/Caches/com.google.Chrome", isDirectory: true)

        for (app, bid, name) in [
            (chromeApp, "com.google.Chrome", "Google Chrome"),
            (driveApp, "com.google.drivefs", "Google Drive"),
        ] {
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": bid,
                "CFBundleName": name,
                "CFBundleExecutable": name,
                "CFBundleShortVersionString": "1.0",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try FileManager.default.createDirectory(at: chromeDefault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chromeCache, withIntermediateDirectories: true)

        let isolatedService = UninstallerService(
            fileSystemContext: ctx
        )

        let scannedChrome = try await isolatedService.scan(appURL: chromeApp)
        let deepChrome = try await isolatedService.deepScan(scannedChrome, mode: .balanced)
        let browserItems = deepChrome.relatedFiles.filter { $0.isBrowserData }
        XCTAssertFalse(browserItems.isEmpty)
        XCTAssertTrue(browserItems.allSatisfy { !$0.isSelected && $0.deletionRisk == .normal })

        let scannedDrive = try await isolatedService.scan(appURL: driveApp)
        let deepDrive = try await isolatedService.deepScan(scannedDrive, mode: .balanced)
        XCTAssertFalse(deepDrive.relatedFiles.contains { $0.url.path.lowercased().contains("/google/chrome") })
    }

    func testSpotlightDisabled_doesNotCrashAndFallsBackSafely() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }

        let appURL = ctx.homeDirectory.appendingPathComponent("Applications/NoSpotlight.app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.nospotlight",
            "CFBundleName": "NoSpotlight",
            "CFBundleExecutable": "NoSpotlight",
            "CFBundleShortVersionString": "1.0",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        SpotlightMetadata.setOverrideForTesting(
            isIndexingAvailable: { _ in false },
            lastUsedDate: { _ in nil }
        )
        defer { SpotlightMetadata.resetForTesting() }

        XCTAssertFalse(SpotlightMetadata.isIndexingAvailable(at: ctx.homePath))
        let missingURL = ctx.homeDirectory.appendingPathComponent("Missing.app")
        XCTAssertNil(SpotlightMetadata.lastUsedDate(for: missingURL))

        let isolatedService = UninstallerService(
            fileSystemContext: ctx
        )
        let info = try await isolatedService.scan(appURL: appURL)
        XCTAssertEqual(info.bundleID, "com.example.nospotlight")
    }

    func testCrashSignalHandler_installsResethandSigaction() {
        var previous = sigaction()
        sigaction(SIGWINCH, nil, &previous)
        defer { sigaction(SIGWINCH, &previous, nil) }

        CrashSignalHandler.install(signals: [SIGWINCH], installExceptionHandler: false)

        var installed = sigaction()
        let rc = sigaction(SIGWINCH, nil, &installed)
        XCTAssertEqual(rc, 0)
        XCTAssertNotEqual(installed.sa_flags & SA_NODEFER, 0)
        XCTAssertNotNil(installed.__sigaction_u.__sa_handler)

        // Raising a harmless signal (default disposition: ignore) exercises the async-signal-safe
        // handler end-to-end and verifies disposition resets to SIG_DFL.
        Darwin.raise(SIGWINCH)

        var after = sigaction()
        XCTAssertEqual(sigaction(SIGWINCH, nil, &after), 0)
        XCTAssertNil(after.__sigaction_u.__sa_handler)
    }

    func testAppIconCache_downsamplesCachesAndRunsOffMainThread() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }

        let dummyFile = ctx.homeDirectory.appendingPathComponent("DummyApp.app")
        try FileManager.default.createDirectory(at: dummyFile, withIntermediateDirectories: true)

        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var renderCount = 0
            var ranOnMain = false
        }
        let box = Box()

        let cache = AppIconCache(
            countLimit: 10,
            totalCostLimit: 4 * 1024 * 1024,
            maxConcurrentRenders: 2,
            iconRenderer: { _, _ in
                box.lock.lock()
                box.renderCount += 1
                box.ranOnMain = box.ranOnMain || Thread.isMainThread
                box.lock.unlock()

                // Create a large 512x512 bitmap image to verify downsampling.
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Host.rawValue
                guard let cgCtx = CGContext(
                    data: nil,
                    width: 512,
                    height: 512,
                    bitsPerComponent: 8,
                    bytesPerRow: 512 * 4,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                ), let cg = cgCtx.makeImage() else {
                    return nil
                }
                return NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
            }
        )

        let firstIcon = await cache.icon(forPath: dummyFile.path, pixelSize: 64)
        let first = try XCTUnwrap(firstIcon)
        XCTAssertFalse(box.ranOnMain, "Icon rasterization must happen off MainThread")
        let rep = try XCTUnwrap(first.representations.first)
        XCTAssertLessThanOrEqual(rep.pixelsWide, 64)
        XCTAssertLessThanOrEqual(rep.pixelsHigh, 64)

        let second = await cache.icon(forPath: dummyFile.path, pixelSize: 64)
        XCTAssertNotNil(second)
        XCTAssertEqual(box.renderCount, 1, "Second lookup must hit NSCache")

        let missing = await cache.icon(forPath: ctx.homeDirectory.appendingPathComponent("Missing.app").path, pixelSize: 64)
        XCTAssertNil(missing)
    }

    func testBoundedConcurrency_capsActiveWorkers() async throws {
        final class Tracker: @unchecked Sendable {
            let lock = NSLock()
            var active = 0
            var peak = 0
            func enter() {
                lock.lock()
                active += 1
                peak = max(peak, active)
                lock.unlock()
            }
            func exit() {
                lock.lock()
                active -= 1
                lock.unlock()
            }
        }
        let tracker = Tracker()
        let inputs = Array(0..<30)
        let results = try await UninstallerService.mapWithBoundedConcurrency(
            items: inputs,
            maxConcurrent: 6
        ) { value in
            tracker.enter()
            try await Task.sleep(for: .milliseconds(15))
            tracker.exit()
            return value * 2
        }

        XCTAssertEqual(results.count, 30)
        XCTAssertLessThanOrEqual(tracker.peak, 6)
        XCTAssertGreaterThan(tracker.peak, 1)
    }

    @MainActor
    func testUninstallerViewModel_loadAppsIfNeededCachesAcrossTabSwitches() async throws {
        final class Counter: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
            func inc() { lock.lock(); count += 1; lock.unlock() }
            func value() -> Int { lock.lock(); defer { lock.unlock() }; return count }
        }
        let counter = Counter()
        let stubApp = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/StubApp.app"),
            bundleID: "com.example.stub",
            name: "StubApp",
            scanState: .deepScanned
        )

        let vm = UninstallerViewModel(
            discoverAppsHandler: {
                counter.inc()
                return [stubApp]
            },
            deepScanHandler: { app, _ in
                var copy = app
                copy.scanState = .deepScanned
                return copy
            }
        )

        vm.loadAppsIfNeeded(mode: .safe)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counter.value(), 1)
        XCTAssertNotNil(vm.lastUpdatedAt)
        XCTAssertEqual(vm.allApps.count, 1)

        // Repeated calls (tab switches) must not rescan.
        for _ in 0..<5 {
            vm.loadAppsIfNeeded(mode: .safe)
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counter.value(), 1)

        // Explicit refresh reloads.
        vm.loadApps(mode: .safe)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counter.value(), 2)
    }

    @MainActor
    func testWorkspaceStore_diskAnalyzerStartsIdleAndViewModelsCache() async {
        let store = WorkspaceStore(journal: TransactionJournal())
        XCTAssertNil(store.diskAnalyzerViewModel.rootURL)
        XCTAssertFalse(store.diskAnalyzerViewModel.isScanning)
        XCTAssertNil(store.diskAnalyzerViewModel.lastUpdatedAt)

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        store.processesViewModel.lastUpdatedAt = fixedDate
        await store.processesViewModel.scanIfNeeded()
        XCTAssertEqual(store.processesViewModel.lastUpdatedAt, fixedDate)

        store.startupServicesViewModel.lastUpdatedAt = fixedDate
        await store.startupServicesViewModel.scanIfNeeded()
        XCTAssertEqual(store.startupServicesViewModel.lastUpdatedAt, fixedDate)
    }

    func testRequiresRestartForRemovedPaths() {
        XCTAssertTrue(UninstallerService.requiresRestartForRemovedPaths([
            URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.helper.plist")
        ]))
        XCTAssertTrue(UninstallerService.requiresRestartForRemovedPaths([
            URL(fileURLWithPath: "/Library/SystemExtensions/1234/com.example.ext.systemextension")
        ]))
        XCTAssertTrue(UninstallerService.requiresRestartForRemovedPaths([
            URL(fileURLWithPath: "/Library/Extensions/ExampleDriver.kext")
        ]))
        XCTAssertTrue(UninstallerService.requiresRestartForRemovedPaths([
            URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.example.tool")
        ]))
        XCTAssertTrue(UninstallerService.requiresRestartForRemovedPaths([
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/ExampleAudio.driver")
        ]))
        XCTAssertTrue(UninstallerService.requiresRestartForRemovedPaths([
            URL(fileURLWithPath: "/Applications/Example.app"),
            URL(fileURLWithPath: "/tmp/Custom.kext")
        ]))

        XCTAssertFalse(UninstallerService.requiresRestartForRemovedPaths([
            URL(fileURLWithPath: "/Applications/Example.app"),
            URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/com.example.agent.plist"),
            URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.app"),
            URL(fileURLWithPath: "/Users/test/Library/Preferences/com.example.app.plist")
        ]))
    }
}
