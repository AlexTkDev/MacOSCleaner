import XCTest
@testable import MacOSCleaner

final class PreReleaseAuditTests: XCTestCase {
    private var fileSystemContext: FileSystemContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
    }

    override func tearDownWithError() throws {
        SpotlightMetadata.resetForTesting()
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func createSyntheticApp(
        in directory: URL,
        name: String,
        bundleID: String,
        version: String = "1.0.0",
        isElectron: Bool = false,
        payloadBytes: Int = 512
    ) throws -> URL {
        let fm = FileManager.default
        let appURL = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundleShortVersionString": version,
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        if payloadBytes > 0 {
            let macOSDir = contents.appendingPathComponent("MacOS", isDirectory: true)
            try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
            try Data(repeating: 0x5A, count: payloadBytes).write(to: macOSDir.appendingPathComponent(name))
        }

        if isElectron {
            let framework = contents.appendingPathComponent("Frameworks/Electron Framework.framework", isDirectory: true)
            try fm.createDirectory(at: framework, withIntermediateDirectories: true)
        }

        return appURL
    }

    // MARK: - 1. 400+ Apps Stress Simulation (Spotlight off + bounded concurrency + icon cache)

    func testStress_420Apps_discoveryWithSpotlightDisabledAndBrokenSymlinks() async throws {
        let fm = FileManager.default
        let appsDir = fileSystemContext.homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        let utilitiesDir = appsDir.appendingPathComponent("Utilities", isDirectory: true)
        try fm.createDirectory(at: utilitiesDir, withIntermediateDirectories: true)

        // 410 normal apps + 5 Electron apps + 5 nested utilities = 420 listable apps
        for i in 0..<410 {
            try createSyntheticApp(
                in: appsDir,
                name: String(format: "StressApp%03d", i),
                bundleID: String(format: "com.example.stressapp%03d", i),
                payloadBytes: 256
            )
        }
        for i in 0..<5 {
            let name = "ElectronTool\(i)"
            let bid = "com.example.electrontool\(i)"
            try createSyntheticApp(in: appsDir, name: name, bundleID: bid, isElectron: true, payloadBytes: 256)
            // Companion helper bundle that should collapse into parent
            try createSyntheticApp(in: appsDir, name: "\(name) Helper", bundleID: "\(bid).helper", payloadBytes: 128)
        }
        for i in 0..<5 {
            try createSyntheticApp(
                in: utilitiesDir,
                name: "NestedUtil\(i)",
                bundleID: "com.example.nestedutil\(i)",
                payloadBytes: 256
            )
        }

        // Malformed .app without Info.plist (must be skipped cleanly, not crash)
        let malformed = appsDir.appendingPathComponent("CorruptEmpty.app", isDirectory: true)
        try fm.createDirectory(at: malformed, withIntermediateDirectories: true)

        // Broken symlink simulating an unplugged USB drive app (must be skipped cleanly)
        let brokenLink = appsDir.appendingPathComponent("UnpluggedUSBApp.app")
        try fm.createSymbolicLink(atPath: brokenLink.path, withDestinationPath: "/Volumes/UnpluggedUSB_\(UUID().uuidString)/Missing.app")

        // Simulate Spotlight completely disabled (issue #39)
        SpotlightMetadata.setOverrideForTesting(
            isIndexingAvailable: { _ in false },
            lastUsedDate: { _ in nil }
        )

        let discovery = AppDiscovery(
            homebrewCellarDirectories: [],
            searchDirectories: [appsDir]
        )
        let service = UninstallerService(
            fileSystemContext: fileSystemContext,
            appDiscovery: discovery
        )

        let clock = ContinuousClock()
        let start = clock.now
        let discovered = try await service.scanAllApplications()
        let elapsed = clock.now - start

        XCTAssertEqual(discovered.count, 420, "All 420 primary apps should be discovered while helpers collapse and broken/corrupt bundles skip")
        XCTAssertLessThan(elapsed, .seconds(15), "420-app discovery with in-process SecStaticCode should finish fast, took \(elapsed)")
        XCTAssertFalse(discovered.contains { $0.name == "CorruptEmpty" })
        XCTAssertFalse(discovered.contains { $0.name == "UnpluggedUSBApp" })
    }

    func testStress_420Icons_appIconCacheBoundsConcurrencyAndDownsamples() async throws {
        let fm = FileManager.default
        let appsDir = fileSystemContext.homeDirectory.appendingPathComponent("IconStressApps", isDirectory: true)
        try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)

        var paths: [String] = []
        for i in 0..<420 {
            let dir = appsDir.appendingPathComponent("App\(i).app", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            paths.append(dir.path)
        }

        final class ConcurrencyTracker: @unchecked Sendable {
            let lock = NSLock()
            var active = 0
            var peak = 0
            var totalRenders = 0
            var anyOnMain = false
        }
        let tracker = ConcurrencyTracker()

        let cache = AppIconCache(
            countLimit: 512,
            totalCostLimit: 32 * 1024 * 1024,
            maxConcurrentRenders: 4,
            iconRenderer: { _, _ in
                tracker.lock.lock()
                tracker.active += 1
                tracker.peak = max(tracker.peak, tracker.active)
                tracker.totalRenders += 1
                tracker.anyOnMain = tracker.anyOnMain || Thread.isMainThread
                tracker.lock.unlock()

                let cs = CGColorSpaceCreateDeviceRGB()
                let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Host.rawValue
                let img: NSImage? = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4, space: cs, bitmapInfo: info)
                    .flatMap { $0.makeImage() }
                    .map { NSImage(cgImage: $0, size: NSSize(width: 128, height: 128)) }

                tracker.lock.lock()
                tracker.active -= 1
                tracker.lock.unlock()
                return img
            }
        )

        var loadedCount = 0
        await withTaskGroup(of: NSImage?.self) { group in
            for path in paths {
                group.addTask {
                    await cache.icon(forPath: path, pixelSize: 64)
                }
            }
            for await image in group {
                if let image {
                    loadedCount += 1
                    if let rep = image.representations.first {
                        XCTAssertLessThanOrEqual(rep.pixelsWide, 64)
                        XCTAssertLessThanOrEqual(rep.pixelsHigh, 64)
                    }
                }
            }
        }

        XCTAssertEqual(loadedCount, 420)
        XCTAssertLessThanOrEqual(tracker.peak, 4, "RenderGate must cap concurrent icon renders at 4")
        XCTAssertFalse(tracker.anyOnMain, "Icon rasterization must never run on MainThread")
    }

    @MainActor
    func testUninstallerViewModel_userCheckboxEditSurvivesBackgroundDeepScanAndSpotlightUpdatesAsync() async throws {
        SpotlightMetadata.setOverrideForTesting(
            isIndexingAvailable: { _ in false },
            lastUsedDate: { _ in nil }
        )

        let apps = (0..<25).map { i in
            UninstallerService.AppInfo(
                url: fileSystemContext.homeDirectory.appendingPathComponent("Applications/App\(i).app"),
                bundleID: "com.example.app\(i)",
                name: "App\(i)",
                scanState: .discovered
            )
        }
        let targetApp = apps[20]
        let relatedURL = fileSystemContext.homeDirectory.appendingPathComponent("Library/Caches/com.example.app20")

        let vm = UninstallerViewModel(
            discoverAppsHandler: { apps },
            deepScanHandler: { app, _ in
                try? await Task.sleep(for: .milliseconds(10))
                var copy = app
                copy.scanState = .deepScanned
                if app.bundleID == targetApp.bundleID {
                    copy.relatedFiles = [
                        UninstallerService.RelatedFile(url: relatedURL, isSelected: true, size: 4096)
                    ]
                }
                return copy
            }
        )

        vm.loadApps(mode: .safe)
        // Wait for discovery to finish
        for _ in 0..<50 where vm.isLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(vm.allApps.count, 25)

        // User clicks App #20 while background deep scan is still at early apps
        vm.selectApp(targetApp, mode: .safe)
        for _ in 0..<50 where vm.selectedApp?.scanState != .deepScanned {
            try await Task.sleep(for: .milliseconds(10))
        }
        let file = try XCTUnwrap(vm.selectedApp?.relatedFiles.first)
        XCTAssertTrue(file.isSelected)

        // User unchecks the related file
        vm.toggleSelection(file, in: try XCTUnwrap(vm.selectedApp))
        XCTAssertEqual(vm.selectedApp?.relatedFiles.first?.isSelected, false)

        // Wait for background deep scan loop to finish all 25 apps
        for _ in 0..<100 where vm.isDeepScanning {
            try await Task.sleep(for: .milliseconds(20))
        }

        // User's checkbox edit must NOT be overwritten by background deepScan loop
        let finalApp = try XCTUnwrap(vm.allApps.first(where: { $0.bundleID == targetApp.bundleID }))
        XCTAssertEqual(finalApp.relatedFiles.first?.isSelected, false, "Background deepScan must preserve user checkbox toggles")
        XCTAssertEqual(vm.selectedApp?.relatedFiles.first?.isSelected, false)
        XCTAssertFalse(vm.isSpotlightAvailable, "Async Spotlight probe must reflect disabled Spotlight")
    }

    // MARK: - 2. External SSD & USB Flash Drive Scenarios

    func testExternalVolumes_safetyPolicyMatrix() {
        let prod = FileSystemContext.production
        let safety = SafetyManager(homeDirectory: prod.homePath, fileSystemContext: prod)

        // Apps & user files on external SSD / USB flash drive: allowed for uninstall & userSelected, NEVER cleanup
        let ssdApp = URL(fileURLWithPath: "/Volumes/SamsungSSD/Applications/BigGame.app")
        let usbApp = URL(fileURLWithPath: "/Volumes/USB_Flash/PortableTool.app")
        let ssdVideo = URL(fileURLWithPath: "/Volumes/SamsungSSD/Movies/clip.mov")

        XCTAssertNoThrow(try safety.validate(url: ssdApp, policy: .uninstall))
        XCTAssertNoThrow(try safety.validate(url: ssdApp, policy: .uninstallApp(bundleID: "com.example.biggame")))
        XCTAssertNoThrow(try safety.validate(url: usbApp, policy: .uninstall))
        XCTAssertNoThrow(try safety.validate(url: ssdVideo, policy: .userSelected))

        // Automated cleanup must NEVER touch external volumes
        XCTAssertThrowsError(try safety.validate(url: ssdApp, policy: .cleanup))
        XCTAssertThrowsError(try safety.validate(url: ssdVideo, policy: .cleanup))

        // Mount roots, Time Machine, volume metadata, and OS dirs on bootable external disks must ALWAYS be refused
        let alwaysRefused: [String] = [
            "/Volumes",
            "/Volumes/SamsungSSD",
            "/Volumes/TimeMachine/Backups.backupdb/Mac/file",
            "/Volumes/My Time Machine/Apps/Foo.app",
            "/Volumes/.timemachine/snapshot/Foo.app",
            "/Volumes/Recovery/boot",
            "/Volumes/SamsungSSD/.Spotlight-V100/Store-V2",
            "/Volumes/SamsungSSD/.fseventsd/00001",
            "/Volumes/SamsungSSD/.Trashes/501/item",
            "/Volumes/SamsungSSD/Backups.backupdb/snap",
            "/Volumes/SamsungSSD/System/Library/CoreServices",
            "/Volumes/SamsungSSD/usr/bin/env",
            "/Volumes/SamsungSSD/Library/Application Support/Apple/Asset",
            "/Volumes/SamsungSSD/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for path in alwaysRefused {
            let url = URL(fileURLWithPath: path)
            XCTAssertThrowsError(try safety.validate(url: url, policy: .uninstall), "Must refuse \(path) in .uninstall")
            XCTAssertThrowsError(try safety.validate(url: url, policy: .userSelected), "Must refuse \(path) in .userSelected")
            XCTAssertThrowsError(try safety.validate(url: url, policy: .cleanup), "Must refuse \(path) in .cleanup")
        }

        // Root volume symlink (/Volumes/Macintosh HD/System/...) must remain hard-refused
        if FileManager.default.fileExists(atPath: "/Volumes/Macintosh HD") {
            let rootViaVolumes = URL(fileURLWithPath: "/Volumes/Macintosh HD/System/Library")
            XCTAssertThrowsError(try safety.validate(url: rootViaVolumes, policy: .userSelected))
            XCTAssertThrowsError(try safety.validate(url: rootViaVolumes, policy: .uninstall))
        }
    }

    func testExternalVolumes_appDiscoveryFindsExternalSSDAppsAndSymlinksAndProtectsFromOrphanScanner() async throws {
        let fm = FileManager.default
        let root = fileSystemContext.allowedRoots[0]
        let localApps = fileSystemContext.homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        let fakeVolumes = root.appendingPathComponent("FakeVolumes", isDirectory: true)
        let ssdApps = fakeVolumes.appendingPathComponent("ExternalSSD/Applications", isDirectory: true)
        let ssdOffload = fakeVolumes.appendingPathComponent("ExternalSSD/Offloaded", isDirectory: true)
        let tmApps = fakeVolumes.appendingPathComponent("TimeMachineBackup/Applications", isDirectory: true)

        try fm.createDirectory(at: localApps, withIntermediateDirectories: true)
        try fm.createDirectory(at: ssdApps, withIntermediateDirectories: true)
        try fm.createDirectory(at: ssdOffload, withIntermediateDirectories: true)
        try fm.createDirectory(at: tmApps, withIntermediateDirectories: true)

        // 1. App installed directly on ExternalSSD/Applications
        try createSyntheticApp(in: ssdApps, name: "ExternalGame", bundleID: "com.example.externalgame")

        // 2. App stored on ExternalSSD and symlinked into ~/Applications
        let offloadedTarget = try createSyntheticApp(in: ssdOffload, name: "SymlinkedEditor", bundleID: "com.example.symlinkededitor")
        let appSymlink = localApps.appendingPathComponent("SymlinkedEditor.app")
        try fm.createSymbolicLink(at: appSymlink, withDestinationURL: offloadedTarget)

        // 3. App on Time Machine backup volume (must NOT be discovered!)
        try createSyntheticApp(in: tmApps, name: "BackupOnlyApp", bundleID: "com.example.backuponly")

        // 4. Broken symlink for unplugged flash drive (must NOT crash or appear)
        let unpluggedLink = localApps.appendingPathComponent("UnpluggedStickApp.app")
        try fm.createSymbolicLink(atPath: unpluggedLink.path, withDestinationPath: "/Volumes/MissingUSB_\(UUID().uuidString)/App.app")

        let discovery = AppDiscovery(
            homebrewCellarDirectories: [],
            searchDirectories: [localApps],
            externalVolumesRoot: fakeVolumes
        )
        let discoveredURLs = await discovery.findAll()
        let discoveredNames = Set(discoveredURLs.map { $0.deletingPathExtension().lastPathComponent })

        XCTAssertTrue(discoveredNames.contains("ExternalGame"), "Should discover apps under <ExternalSSD>/Applications")
        XCTAssertTrue(discoveredNames.contains("SymlinkedEditor"), "Should discover symlinked .app bundles pointing to external SSD")
        XCTAssertFalse(discoveredNames.contains("BackupOnlyApp"), "Must skip Time Machine backup volumes")
        XCTAssertFalse(discoveredNames.contains("UnpluggedStickApp"), "Must safely skip broken symlinks to unplugged USB drives")

        // Verify OrphanScanner does NOT treat ExternalGame's ~/Library data as orphaned!
        let appSupport = fileSystemContext.homeDirectory
            .appendingPathComponent("Library/Application Support/com.example.externalgame", isDirectory: true)
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16 * 1024).write(to: appSupport.appendingPathComponent("save.dat"))

        let safety = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        let orphanScanner = OrphanScanner(
            safetyManager: safety,
            fileSystemContext: fileSystemContext,
            appDiscovery: discovery
        )
        let orphans = try await orphanScanner.scanOrphans()
        XCTAssertFalse(
            orphans.contains { $0.url.path.lowercased().contains("externalgame") },
            "Data belonging to an app installed on an external SSD must NEVER be flagged as an orphan"
        )
    }

    func testExternalVolumes_duplicateFinderAllowsExplicitExternalVolumeOnly() async {
        let engine = DuplicateFinderEngine()
        let extPhoto = "/Volumes/ExternalSSD/Photos/IMG_0001.jpg"
        let tmFile = "/Volumes/TimeMachine/Backups.backupdb/IMG_0001.jpg"
        let extSystem = "/Volumes/ExternalSSD/System/Library/data.bin"

        let allowedExplicit = await engine.isSafeUserFilePath(extPhoto, allowExternalVolumes: true)
        let blockedImplicit = await engine.isSafeUserFilePath(extPhoto, allowExternalVolumes: false)
        let blockedTM = await engine.isSafeUserFilePath(tmFile, allowExternalVolumes: true)
        let blockedSys = await engine.isSafeUserFilePath(extSystem, allowExternalVolumes: true)

        XCTAssertTrue(allowedExplicit, "Explicitly chosen external SSD folder must be scannable in Duplicates")
        XCTAssertFalse(blockedImplicit, "Implicit home scan must never roam into /Volumes")
        XCTAssertFalse(blockedTM, "Time Machine backups on external drives must never be scanned")
        XCTAssertFalse(blockedSys, "OS system dirs on bootable external drives must never be scanned")
    }

    func testUninstall_unpluggedOrReadOnlyAppReportsFailureInsteadOfSilentSuccess() async throws {
        let fm = FileManager.default
        let appsDir = fileSystemContext.homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        let cacheDir = fileSystemContext.homeDirectory.appendingPathComponent("Library/Caches/com.example.lockedapp", isDirectory: true)
        let trashDir = fileSystemContext.allowedRoots[0].appendingPathComponent("IsolatedTrash", isDirectory: true)
        try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(to: cacheDir.appendingPathComponent("cache.bin"))

        // Case 1: App bundle disappeared (unplugged USB drive) before uninstall — fails cleanly, no crash
        let missingApp = UninstallerService.AppInfo(
            url: appsDir.appendingPathComponent("Unplugged.app"),
            bundleID: "com.example.unplugged",
            name: "Unplugged"
        )
        let safety = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)
        let service = UninstallerService(
            safetyManager: safety,
            trashManager: trash,
            fileSystemContext: fileSystemContext
        )

        do {
            _ = try await service.uninstall(app: missingApp, bypassTrash: false, removeFromDock: false)
            XCTFail("Uninstalling an unplugged/missing app with no other targets should throw")
        } catch {
            // Expected failure
        }

        // Case 2: App bundle on read-only directory while related cache succeeds — app.url must appear in failedDeletions
        let readOnlyDir = appsDir.appendingPathComponent("ReadOnlyVolume", isDirectory: true)
        try fm.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        let lockedAppURL = try createSyntheticApp(in: readOnlyDir, name: "LockedApp", bundleID: "com.example.lockedapp")
        // Make parent read-only so moving LockedApp.app fails (simulates read-only DMG/USB)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path) }

        let lockedInfo = UninstallerService.AppInfo(
            url: lockedAppURL,
            bundleID: "com.example.lockedapp",
            name: "LockedApp",
            relatedFiles: [
                UninstallerService.RelatedFile(url: cacheDir, isSelected: true, size: 4096)
            ]
        )

        let report = try await service.uninstall(app: lockedInfo, bypassTrash: false, removeFromDock: false)
        XCTAssertTrue(fm.fileExists(atPath: lockedAppURL.path), "App in read-only parent should remain on disk")
        let failedURLs = Set((report?.failedDeletions ?? []).map { NormalizedPath.key($0.url) })
        XCTAssertTrue(
            failedURLs.contains(NormalizedPath.key(lockedAppURL)),
            "Uninstall must report failed app.url in failedDeletions instead of silently claiming success"
        )
    }

    // MARK: - 3. Disabled macOS Features (Spotlight, FDA, Time Machine, Xcode/CLT, Apple Intelligence)

    func testDisabledFeatures_noXcodeCLTDoesNotInvokeXcrun() async throws {
        final class CallRecorder: @unchecked Sendable {
            let lock = NSLock()
            var commands: [String] = []
            func record(_ cmd: String) {
                lock.lock(); commands.append(cmd); lock.unlock()
            }
            func snapshot() -> [String] {
                lock.lock(); defer { lock.unlock() }; return commands
            }
        }
        let recorder = CallRecorder()
        let mock = MockCommandRunner()
        mock.runHandler = { cmd, args in
            recorder.record(([cmd] + args).joined(separator: " "))
            if cmd == "/usr/bin/xcode-select" {
                return CommandResult(stdout: "", stderr: "xcode-select: error: unable to get active developer directory", exitCode: 2)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 1)
        }

        // Create CoreSimulator folder so the guard actually reaches xcode-select check
        let simDir = fileSystemContext.homeDirectory.appendingPathComponent("Library/Developer/CoreSimulator", isDirectory: true)
        try FileManager.default.createDirectory(at: simDir, withIntermediateDirectories: true)

        let engine = CleanupEngine(commandRunner: mock, fileSystemContext: fileSystemContext)
        _ = try await engine.run(categories: [.iosSimulators], dryRun: true)

        let ran = recorder.snapshot()
        XCTAssertFalse(
            ran.contains { $0.contains("xcrun") || $0.contains("simctl") },
            "Must never invoke /usr/bin/xcrun shim when Xcode is absent (avoids macOS CLT install popup): \(ran)"
        )
    }

    func testDisabledFeatures_timeMachineDisabledAndTCCNoFDAAndAppleIntelligenceRestricted() async {
        // 1. Time Machine daemon disabled / tmutil fails
        let tmMock = MockCommandRunner()
        tmMock.runHandler = { _, _ in
            CommandResult(stdout: "", stderr: "The operation couldn't be completed (Time Machine disabled)", exitCode: 1)
        }
        let snapshots = await TimeMachineScanner.listLocalSnapshots(commandRunner: tmMock)
        XCTAssertTrue(snapshots.isEmpty)

        // 2. TCC database inaccessible without FDA
        let missingDB = fileSystemContext.homeDirectory.appendingPathComponent("NoSuchTCC.db").path
        let tccService = TCCService(
            commandRunner: MockCommandRunner(),
            userDBPath: missingDB,
            systemDBPath: missingDB,
            hasFullDiskAccessProvider: { false }
        )
        let tccSnapshot = await tccService.loadSnapshot()
        XCTAssertTrue(tccSnapshot.groups.isEmpty)

        // 3. Apple Intelligence assets missing / restricted
        let missingAssets = fileSystemContext.homeDirectory.appendingPathComponent("MissingAssetsV2").path
        let aiSnap = AppleIntelligenceStorageReader.inspect(
            components: [.init(id: "test", titleKey: "test", path: missingAssets)],
            baseModelPath: missingAssets
        )
        XCTAssertTrue(aiSnap.components.isEmpty)
        XCTAssertTrue(aiSnap.isBaseModelAccessRestricted)
        XCTAssertNil(aiSnap.baseModelReadableBytes)
    }

    func testDisabledFeatures_cleanupHandlesUnreadableCacheDirWithoutCrashing() async throws {
        let fm = FileManager.default
        let cachesDir = fileSystemContext.homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        let lockedDir = cachesDir.appendingPathComponent("com.example.lockedcache", isDirectory: true)
        let readableDir = cachesDir.appendingPathComponent("com.example.readablecache", isDirectory: true)
        try fm.createDirectory(at: lockedDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: readableDir, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 8192).write(to: lockedDir.appendingPathComponent("secret.bin"))
        try Data(repeating: 0x22, count: 8192).write(to: readableDir.appendingPathComponent("temp.bin"))

        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path) }

        let safety = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        let engine = CleanupEngine(safetyManager: safety, fileSystemContext: fileSystemContext)

        var options = CleanupOptions()
        options.bypassTrash = true
        let results = try await engine.run(categories: [.appCaches], dryRun: false, options: options)
        XCTAssertFalse(results.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: readableDir.appendingPathComponent("temp.bin").path), "Readable third-party cache must still clean despite EPERM sibling")
    }

    // MARK: - 4. End-to-End Browser Extensions & Banking Data Protection (Jovo complaint)

    func testBrowserProtection_fullCleanupAndChromeUninstallAndPWAShimNeverDestroyExtensions() async throws {
        let fm = FileManager.default
        let home = fileSystemContext.homeDirectory
        let chromeRoot = home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        let profile = chromeRoot.appendingPathComponent("Default", isDirectory: true)

        // Critical user/banking extension & session artifacts that must NEVER be touched by Cleanup
        let protectedFiles: [URL] = [
            profile.appendingPathComponent("Extensions/bankext123/1.0/manifest.json"),
            profile.appendingPathComponent("Extensions/bankext123/1.0/cache/payment_cert.bin"),
            profile.appendingPathComponent("Local Extension Settings/bankext123/000003.log"),
            profile.appendingPathComponent("Local Storage/leveldb/000003.log"),
            profile.appendingPathComponent("IndexedDB/https_bank.example.com_0.indexeddb.leveldb/000003.log"),
            profile.appendingPathComponent("Cookies"),
            profile.appendingPathComponent("Login Data"),
            profile.appendingPathComponent("Secure Preferences"),
            chromeRoot.appendingPathComponent("NativeMessagingHosts/com.bank.signer.json"),
        ]
        for file in protectedFiles {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 4096).write(to: file)
        }

        // Allowed regenerable Chrome caches
        let allowedCacheFile = profile.appendingPathComponent("Cache/Cache_Data/f_0001")
        let allowedCodeCache = profile.appendingPathComponent("Code Cache/js/c_0001")
        for file in [allowedCacheFile, allowedCodeCache] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xCD, count: 8192).write(to: file)
        }

        let trashDir = fileSystemContext.allowedRoots[0].appendingPathComponent("CleanupTrash", isDirectory: true)
        try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let safety = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        let trash = TrashManager(safetyManager: safety, trashDirectoryURL: trashDir)

        // Step 1: Run Cleanup across browser, chromeExtra, appCaches, ideCaches, dynamicCacheDiscovery
        let engine = CleanupEngine(safetyManager: safety, fileSystemContext: fileSystemContext)
        var cleanupOptions = CleanupOptions()
        cleanupOptions.bypassTrash = true
        _ = try await engine.run(
            categories: [.browserCaches, .chromeExtraCaches, .appCaches, .ideCaches, .dynamicCacheDiscovery],
            dryRun: false,
            options: cleanupOptions
        )

        for file in protectedFiles {
            XCTAssertTrue(fm.fileExists(atPath: file.path), "Cleanup MUST NEVER delete \(file.path)")
        }
        XCTAssertFalse(fm.fileExists(atPath: allowedCacheFile.path), "Allowed Chrome Cache_Data should be cleaned")
        XCTAssertFalse(fm.fileExists(atPath: allowedCodeCache.path), "Allowed Chrome Code Cache should be cleaned")

        // Step 2: Uninstall a Chrome PWA banking app — Chrome profile & extensions must stay 100% untouched
        let appsDir = home.appendingPathComponent("Applications", isDirectory: true)
        let pwaApp = try createSyntheticApp(in: appsDir, name: "MyBank Payment", bundleID: "com.google.Chrome.app.bankpay123")
        let service = UninstallerService(safetyManager: safety, trashManager: trash, fileSystemContext: fileSystemContext)

        let scannedPWA = try await service.scan(appURL: pwaApp)
        let deepPWA = try await service.deepScan(scannedPWA, mode: .balanced)
        XCTAssertFalse(deepPWA.relatedFiles.contains { $0.url.path.lowercased().contains("/google/chrome") })
        _ = try await service.uninstall(app: deepPWA, bypassTrash: false, removeFromDock: false)

        for file in protectedFiles {
            XCTAssertTrue(fm.fileExists(atPath: file.path), "Uninstalling Chrome PWA must NEVER touch \(file.path)")
        }

        // Step 3: Uninstall Chrome with browser data left unselected (default) —
        // VerificationEngine must NOT surface intentionally kept browser data as pre-selected leftovers.
        let chromeApp = try createSyntheticApp(in: appsDir, name: "Google Chrome", bundleID: "com.google.Chrome")
        let scannedChrome = try await service.scan(appURL: chromeApp)
        let deepChrome = try await service.deepScan(scannedChrome, mode: .balanced)
        XCTAssertTrue(
            deepChrome.relatedFiles.filter(\.isBrowserData).allSatisfy { !$0.isSelected },
            "Chrome browser data must be unselected by default"
        )

        let report = try await service.uninstall(app: deepChrome, bypassTrash: false, removeFromDock: false)
        for file in protectedFiles {
            XCTAssertTrue(fm.fileExists(atPath: file.path), "Keeping Chrome profile unchecked must preserve \(file.path)")
        }
        if let report {
            XCTAssertFalse(
                report.items.contains { $0.isSelected && safety.isBrowserUserDataPath($0.url.path) },
                "Post-uninstall verification must never pre-select kept browser user data"
            )
        }
    }
}
