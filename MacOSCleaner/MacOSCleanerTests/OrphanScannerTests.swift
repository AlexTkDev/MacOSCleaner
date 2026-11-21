import XCTest
@testable import MacOSCleaner

final class OrphanScannerTests: XCTestCase {
    var fileSystemContext: FileSystemContext!
    var testRoot: URL!
    var safetyManager: SafetyManager!
    var mockRunner: MockCommandRunner!
    var plistCache: PlistContentCache!
    var codesignCache: CodesignCache!
    var scanner: OrphanScanner!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        testRoot = fileSystemContext.homeDirectory
        safetyManager = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        mockRunner = MockCommandRunner()
        plistCache = PlistContentCache()
        codesignCache = CodesignCache()
        scanner = OrphanScanner(
            safetyManager: safetyManager,
            commandRunner: CommandRunner(),
            fileSystemContext: fileSystemContext,
            codesignCache: codesignCache,
            plistCache: plistCache
        )
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        scanner = nil
        safetyManager = nil
        fileSystemContext = nil
        testRoot = nil
        try super.tearDownWithError()
    }

    func testOrphanScannerInitialization() {
        XCTAssertNotNil(scanner)
    }

    func testOrphanItemModel_calculatesProperties() {
        let dummyURL = URL(fileURLWithPath: "/Users/test/Library/Preferences/com.example.orphan.plist")
        let item = OrphanItem(
            url: dummyURL,
            name: "Orphan",
            bundleID: "com.example.orphan",
            sizeBytes: 1024,
            category: "Preferences",
            evidence: [.bundleIDExact, .plistContent],
            confidence: .veryLikely,
            score: 80,
            isSelected: true
        )

        XCTAssertEqual(item.name, "Orphan")
        XCTAssertEqual(item.bundleID, "com.example.orphan")
        XCTAssertEqual(item.sizeBytes, 1024)
        XCTAssertEqual(item.category, "Preferences")
        XCTAssertEqual(item.confidence, .veryLikely)
        XCTAssertEqual(item.score, 80)
        XCTAssertTrue(item.isSelected)
        XCTAssertTrue(item.evidence.contains(.bundleIDExact))
    }

    func testOrphanScanner_scanOrphans_findsUnownedContainer() async throws {
        let containerDir = testRoot
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent("com.unknown.orphanapp", isDirectory: true)
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
        let sampleFile = containerDir.appendingPathComponent("data.bin")
        try Data(repeating: 0xAA, count: 8192).write(to: sampleFile)

        let orphans = try await scanner.scanOrphans()
        XCTAssertFalse(orphans.isEmpty, "Should find unowned container orphan")

        if let found = orphans.first(where: { $0.bundleID == "com.unknown.orphanapp" || $0.name == "Orphanapp" }) {
            XCTAssertEqual(found.category, "Containers")
            XCTAssertGreaterThanOrEqual(found.sizeBytes, 8192)
            XCTAssertTrue(found.evidence.contains(.container) || found.evidence.contains(.bundleIDExact))
            XCTAssertGreaterThanOrEqual(found.confidence, .possible)
        }
    }

    func testOrphanScanner_homebrewFormulaInstalledInCellar_notFlaggedAsOrphan() async throws {
        let cellar = fileSystemContext.allowedRoots[0].appendingPathComponent("Homebrew/Cellar", isDirectory: true)
        let formulaVersionDir = cellar.appendingPathComponent("languagetool/6.5", isDirectory: true)
        try FileManager.default.createDirectory(at: formulaVersionDir, withIntermediateDirectories: true)

        let launchAgents = testRoot.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let plistURL = launchAgents.appendingPathComponent("homebrew.mxcl.languagetool.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": "homebrew.mxcl.languagetool",
                "ProgramArguments": ["/opt/homebrew/opt/languagetool/bin/languagetool-server"]
            ],
            format: .xml,
            options: 0
        )
        try plistData.write(to: plistURL)

        let customScanner = OrphanScanner(
            safetyManager: safetyManager,
            commandRunner: CommandRunner(),
            fileSystemContext: fileSystemContext,
            codesignCache: codesignCache,
            plistCache: plistCache,
            homebrewCellarDirectories: [cellar]
        )

        let orphans = try await customScanner.scanOrphans()
        XCTAssertFalse(
            orphans.contains { $0.url.lastPathComponent == "homebrew.mxcl.languagetool.plist" },
            "Installed Homebrew formula LaunchAgent must not be flagged as orphan"
        )
    }

    func testOrphanScanner_homebrewLaunchAgentWithExistingBinary_notFlaggedAsOrphan() async throws {
        let emptyCellar = fileSystemContext.allowedRoots[0].appendingPathComponent("EmptyCellar", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyCellar, withIntermediateDirectories: true)

        let customBinDir = fileSystemContext.allowedRoots[0].appendingPathComponent("custom-brew/opt/myservice/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: customBinDir, withIntermediateDirectories: true)
        let binaryURL = customBinDir.appendingPathComponent("myservice")
        try Data("#!/bin/sh\n".utf8).write(to: binaryURL)

        let launchAgents = testRoot.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let plistURL = launchAgents.appendingPathComponent("homebrew.mxcl.myservice.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": "homebrew.mxcl.myservice",
                "ProgramArguments": [binaryURL.path, "--daemon"]
            ],
            format: .xml,
            options: 0
        )
        try plistData.write(to: plistURL)

        let customScanner = OrphanScanner(
            safetyManager: safetyManager,
            commandRunner: CommandRunner(),
            fileSystemContext: fileSystemContext,
            codesignCache: codesignCache,
            plistCache: plistCache,
            homebrewCellarDirectories: [emptyCellar]
        )

        let orphans = try await customScanner.scanOrphans()
        XCTAssertFalse(
            orphans.contains { $0.url.lastPathComponent == "homebrew.mxcl.myservice.plist" },
            "Homebrew LaunchAgent whose binary exists on disk must not be flagged as orphan"
        )
    }

    func testOrphanScanner_homebrewFormulaUninstalled_neverMarkedGuaranteed() async throws {
        let emptyCellar = fileSystemContext.allowedRoots[0].appendingPathComponent("EmptyCellar", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyCellar, withIntermediateDirectories: true)

        let launchAgents = testRoot.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let plistURL = launchAgents.appendingPathComponent("homebrew.mxcl.removedtool.plist")
        let missingBin = fileSystemContext.allowedRoots[0].appendingPathComponent("missing-opt/removedtool/bin/removedtool").path
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": "homebrew.mxcl.removedtool",
                "ProgramArguments": [missingBin]
            ],
            format: .xml,
            options: 0
        )
        try plistData.write(to: plistURL)

        let customScanner = OrphanScanner(
            safetyManager: safetyManager,
            commandRunner: CommandRunner(),
            fileSystemContext: fileSystemContext,
            codesignCache: codesignCache,
            plistCache: plistCache,
            homebrewCellarDirectories: [emptyCellar]
        )

        let orphans = try await customScanner.scanOrphans()
        let found = try XCTUnwrap(orphans.first { $0.url.lastPathComponent == "homebrew.mxcl.removedtool.plist" })
        XCTAssertLessThan(found.confidence, .guaranteed, "Uninstalled Homebrew service plist must never be marked Guaranteed")
        XCTAssertEqual(found.confidence, .veryLikely)
        XCTAssertEqual(found.category, "Launch Agents")
    }

    func testExtractBundleIDAndName_versionedPlistAndReverseDNS() {
        let py38 = OrphanScanner.extractBundleIDAndName(from: URL(fileURLWithPath: "/Users/test/Library/Preferences/python3.8.plist"))
        XCTAssertEqual(py38.bundleID, "python3.8")
        XCTAssertEqual(py38.name, "python3.8")

        let py312 = OrphanScanner.extractBundleIDAndName(from: URL(fileURLWithPath: "/Users/test/Library/Preferences/python3.12.plist"))
        XCTAssertEqual(py312.name, "python3.12")

        let orgPy38 = OrphanScanner.extractBundleIDAndName(from: URL(fileURLWithPath: "/Users/test/Library/Preferences/org.python.python3.8.plist"))
        XCTAssertEqual(orgPy38.name, "python3.8")

        let photoshop = OrphanScanner.extractBundleIDAndName(from: URL(fileURLWithPath: "/Users/test/Library/Preferences/com.adobe.Photoshop.2024.plist"))
        XCTAssertEqual(photoshop.name, "Photoshop 2024")

        let oneDrive = OrphanScanner.extractBundleIDAndName(from: URL(fileURLWithPath: "/Users/test/Library/Preferences/com.microsoft.OneDrive.plist"))
        XCTAssertEqual(oneDrive.name, "OneDrive")

        let container = OrphanScanner.extractBundleIDAndName(from: URL(fileURLWithPath: "/Users/test/Library/Containers/com.unknown.orphanapp"))
        XCTAssertEqual(container.bundleID, "com.unknown.orphanapp")
        XCTAssertEqual(container.name, "Orphanapp")

        let cacheFolder = OrphanScanner.extractBundleIDAndName(from: URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.MyApp"))
        XCTAssertEqual(cacheFolder.bundleID, "com.example.MyApp")
        XCTAssertEqual(cacheFolder.name, "MyApp")
    }

    func testOrphanItem_localizedCategory_spanish() {
        LanguageManager.testingLock.lock()
        defer {
            LanguageManager.shared.setLanguage(.english)
            LanguageManager.testingLock.unlock()
        }

        LanguageManager.shared.setLanguage(.spanish)
        XCTAssertEqual(OrphanItem.localizedCategoryName(for: "Preferences"), "Preferencias")
        XCTAssertEqual(OrphanItem.localizedCategoryName(for: "Other"), "Otros")
        XCTAssertEqual(OrphanItem.localizedCategoryName(for: "Launch Agents"), "Agentes de inicio")
    }
}

