import XCTest
import CryptoKit
@testable import MacOSCleaner

final class RegistryPathsTests: XCTestCase {
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

    private func makeCollector() -> CandidateCollector {
        let runner = MockCommandRunner()
        runner.runDelay = .zero
        return CandidateCollector(commandRunner: runner, fileSystemContext: fileSystemContext)
    }

    private struct CatalogSnapshot: Decodable {
        struct Entry: Decodable {
            let name: String
            let bundleIDs: [String]
            let bundleIDPrefixes: [String]
            let pathTemplates: [String]
        }

        let entries: [Entry]
    }

    private func identity(
        bundleID: String,
        appName: String,
        vendorNames: Set<String> = [],
        isDocker: Bool = false,
        isJetBrains: Bool = false
    ) -> AppIdentity {
        AppIdentity(
            bundleID: bundleID,
            appName: appName,
            bundleName: appName,
            bundleVersion: nil,
            executableName: appName,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(appName).app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: vendorNames,
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: isJetBrains, isFlutter: false,
            isJava: false, isQt: false, isDocker: isDocker
        )
    }

    private func allRegistryTemplates() -> Set<String> {
        var templates = Set<String>()
        for appPaths in GeneratedCleanupPaths.registry.values {
            for path in appPaths.paths {
                templates.insert(RegistryPathTemplates.tildeTemplate(path.template))
            }
        }
        return templates
    }

    // MARK: - Registry lookup (migrated from KnownResidualCatalogTests)

    func test_chromeHasRegistryTemplates() {
        let templates = RegistryPathTemplates.uninstallTemplates(forBundleID: "com.google.Chrome")
        XCTAssertFalse(templates.isEmpty)
        XCTAssertTrue(templates.contains { $0.contains("Application Support/Google/Chrome") })
        XCTAssertTrue(templates.contains { $0.contains("Library/Caches") })
        XCTAssertFalse(templates.contains { $0.lowercased().contains("keystone") })
        XCTAssertFalse(templates.contains { $0.lowercased().contains("googlesoftwareupdate") })
    }

    func test_dockerHasRegistryTemplates() {
        let templates = RegistryPathTemplates.uninstallTemplates(forBundleID: "com.docker.docker")
        XCTAssertFalse(templates.isEmpty)
        XCTAssertTrue(templates.contains { $0.contains("group.com.docker") })
        XCTAssertTrue(templates.contains { $0.contains("com.docker.docker") })
        XCTAssertTrue(templates.contains("/Library/LaunchDaemons/com.docker.vmnetd.plist") == false,
                      "Admin paths must not appear in uninstall templates")
    }

    func test_jetbrainsPrefixMatchesFamily() {
        let templates = RegistryPathTemplates.uninstallTemplates(forBundleID: "com.jetbrains.intellij")
        XCTAssertFalse(templates.isEmpty)
        XCTAssertTrue(templates.contains { $0.contains("JetBrains") })
    }

    func test_antigravityIncludesVerifiedDotDirectories() {
        let templates = Set(RegistryPathTemplates.uninstallTemplates(forBundleID: "com.google.antigravity-ide"))
        XCTAssertTrue(templates.contains("~/.antigravity"))
        XCTAssertTrue(templates.contains("~/.antigravity-ide"))
        XCTAssertTrue(templates.contains("~/Library/Application Support/com.google.antigravity-ide"))
    }

    func test_openCodeIncludesAppSpecificDataButNotSharedCLIConfig() {
        let templates = RegistryPathTemplates.uninstallTemplates(forBundleID: "ai.opencode.desktop")
        XCTAssertTrue(templates.contains("~/Library/Application Support/ai.opencode.desktop"))
        XCTAssertTrue(templates.contains("~/Library/Caches/ai.opencode.desktop.ShipIt"))
        XCTAssertFalse(templates.contains { $0.hasPrefix("~/.config/opencode") })
    }

    func test_safariExcludedFromUninstallRegistry() {
        XCTAssertTrue(RegistryPathTemplates.uninstallTemplates(forBundleID: "com.apple.Safari").isEmpty)
    }

    func test_unknownBundleReturnsEmpty() {
        XCTAssertTrue(RegistryPathTemplates.uninstallTemplates(forBundleID: "unknown.com.foo").isEmpty)
        XCTAssertTrue(RegistryPathTemplates.uninstallTemplates(forBundleID: "").isEmpty)
    }

    func test_expandFindsExistingExactPath() throws {
        let home = NSTemporaryDirectory() + "RegistryPathsTests-\(UUID().uuidString)"
        let target = home + "/Library/Caches/com.google.Chrome"
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }

        let found = CleanupPathExpander.expand(
            "~/Library/Caches/com.google.Chrome",
            home: home
        )
        XCTAssertEqual(found, [target])
    }

    func test_collectorIncludesCatalogPath() async throws {
        let cachePath = "\(home)/Library/Caches/com.google.Chrome"
        let created: Bool
        if FileManager.default.fileExists(atPath: cachePath) {
            created = false
        } else {
            try FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
            created = true
        }
        defer {
            if created { try? FileManager.default.removeItem(atPath: cachePath) }
        }

        let collection = await makeCollector().collectDetailed(
            identity: identity(bundleID: "com.google.Chrome", appName: "Google Chrome", vendorNames: ["Google"]),
            mode: .safe
        )
        XCTAssertTrue(
            collection.catalogPaths.contains { $0.path == cachePath },
            "Registry must surface ~/Library/Caches/com.google.Chrome"
        )
        XCTAssertTrue(collection.candidates.contains { $0.path == cachePath })
    }

    func test_registryOwnershipIsBundleSpecific() async throws {
        let chromeCache = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.google.Chrome")
        let googleUpdater = URL(fileURLWithPath: home).appendingPathComponent("Library/Google/GoogleSoftwareUpdate")
        try FileManager.default.createDirectory(at: chromeCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: googleUpdater, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: home).appendingPathComponent("Library")) }

        let collection = await makeCollector().collectDetailed(
            identity: identity(bundleID: "com.google.Chrome", appName: "Google Chrome", vendorNames: ["Google"]),
            mode: .safe
        )

        XCTAssertTrue(collection.candidates.contains { $0.path == chromeCache.path })
        XCTAssertTrue(collection.catalogPaths.contains { $0.path == chromeCache.path })
        XCTAssertTrue(collection.sharedPaths.contains { $0.path == googleUpdater.path })

        let appPaths = try XCTUnwrap(GeneratedCleanupPaths.appPaths(forBundleID: "com.google.Chrome"))
        let adminPaths = appPaths.paths.filter(\.requiresAdmin)
        XCTAssertFalse(adminPaths.isEmpty)
        for entry in adminPaths {
            let resolved = PathToken.home.resolveTemplate(entry.template, home: home)
            XCTAssertFalse(collection.catalogPaths.contains(URL(fileURLWithPath: resolved).standardizedFileURL))
        }
    }

    func test_confidenceKnownCatalogIsGuaranteed() {
        let assessment = ConfidenceEngine.assess(
            [.knownCatalog],
            identity: identity(bundleID: "com.google.Chrome", appName: "Google Chrome")
        )
        XCTAssertEqual(assessment.tier, .guaranteed)
        XCTAssertGreaterThanOrEqual(assessment.score, 100)
    }

    func test_browserRuleMatchesOpera() {
        let rule = BrowserRule()
        XCTAssertTrue(rule.matches(identity: identity(bundleID: "com.operasoftware.Opera", appName: "Opera")))
    }

    func test_embeddedBrowserPathsIncludeAppSupportCaches() {
        let paths = EmbeddedCleanupPaths.paths(for: .browserCaches).map(\.path)
        XCTAssertTrue(paths.contains { $0.contains("Google/Chrome") && $0.contains("Cache") })
        XCTAssertTrue(paths.contains { $0.contains("com.operasoftware.Opera") || $0.contains("Opera") })
    }

    func test_generatedCleanupPathsMerged() {
        let paths = EmbeddedCleanupPaths.paths(for: .browserCaches).map(\.path)
        let generated = GeneratedCleanupPaths.cachePaths(for: .browserCaches).map(\.path)
        XCTAssertFalse(generated.isEmpty)
        for g in generated.prefix(5) {
            XCTAssertTrue(paths.contains(g), "Missing merged path \(g)")
        }
    }

    func test_embeddedPathsExcludeSharedAndAppData() {
        let forbiddenFragments = [
            "GoogleSoftwareUpdate",
            "Application Support/Google/GoogleUpdater",
            "HTTPStorages/com.google.GoogleUpdater",
            "Caches/com.google.SoftwareUpdate",
            "Caches/com.google.GoogleUpdater",
            "Safari/LocalStorage",
            "Safari/Databases",
            "WebKit/com.apple.Safari",
            "Messages/Attachments",
            "JetBrains/Toolbox/apps",
            ".m2/repository",
            "Session Storage",
        ]
        let forbiddenExact = [
            "~/Library/Caches/Google",
            "~/Library/Application Support/Google/Chrome/Default/Service Worker",
            "~/Library/Application Support/Cursor/Service Worker",
            "~/Library/Application Support/Code/Service Worker",
            "~/Library/Application Support/Windsurf/Service Worker",
            "~/Library/Application Support/Claude/Service Worker",
            "~/Library/Application Support/ChatGPT/Service Worker",
            "~/Library/Application Support/Slack/Service Worker",
            "~/Library/Application Support/ai.opencode.desktop/Service Worker",
            "~/Library/Application Support/Cursor/Session Storage",
            "~/Library/Application Support/Code/Session Storage",
            "~/Library/Application Support/Slack/Session Storage",
        ]
        let categories: [CleanupCategory] = [
            .appCaches, .browserCaches, .messagingMedia, .ideCaches, .languageCaches,
            .dotfileCaches, .systemCaches,
        ]
        for category in categories {
            let paths = EmbeddedCleanupPaths.paths(for: category).map(\.path)
            for fragment in forbiddenFragments {
                XCTAssertFalse(
                    paths.contains { $0.contains(fragment) },
                    "\(fragment) must not appear in \(category) cleanup paths"
                )
            }
            for exact in forbiddenExact {
                XCTAssertFalse(
                    paths.contains(exact),
                    "\(exact) must not be an exact cleanup path in \(category)"
                )
            }
        }
    }

    func test_cachePathsSubsetOfEmbeddedMerge() {
        for category in [
            CleanupCategory.browserCaches, .ideCaches, .appCaches, .dotfileCaches,
            .messagingMedia, .languageCaches, .systemCaches,
        ] {
            let merged = Set(EmbeddedCleanupPaths.paths(for: category).map(\.path))
            let generated = Set(GeneratedCleanupPaths.cachePaths(for: category).map(\.path))
            XCTAssertTrue(generated.isSubset(of: merged), "Generated cache paths must merge into \(category)")
        }
    }

    func test_generatedSourceHashMatchesSoTIfAvailable() throws {
        guard let url = Self.testResourceURL(name: "engine_paths", extension: "json") else {
            throw XCTSkip("engine_paths.json missing from bundle")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(GeneratedCleanupPaths.sourceHash, digest)
    }

    // MARK: - Superset coverage (legacy KnownResidualCatalog snapshot)

    func test_registryCoversLegacyCatalogPathsPerBundle() throws {
        let url = try XCTUnwrap(
            Self.testResourceURL(name: "known_residual_catalog_snapshot", extension: "json"),
            "known_residual_catalog_snapshot.json missing from test bundle"
        )
        let snapshot = try JSONDecoder().decode(CatalogSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(snapshot.entries.count, 114)

        var missing: [(entry: String, bundleID: String, path: String)] = []
        for entry in snapshot.entries {
            for bundleID in entry.bundleIDs {
                guard let appPaths = GeneratedCleanupPaths.appPaths(forBundleID: bundleID) else {
                    missing.append((entry.name, bundleID, "<missing registry entry>"))
                    continue
                }
                let registry = Set(appPaths.paths.map { RegistryPathTemplates.tildeTemplate($0.template) })
                for template in entry.pathTemplates where !registry.contains(template) {
                    missing.append((entry.name, bundleID, template))
                }
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            "Registry missing \(missing.count) bundle-owned path(s): " +
            missing.prefix(10).map { "\($0.entry) [\($0.bundleID)]: \($0.path)" }.joined(separator: "; ")
        )
    }

    private static func testResourceURL(name: String, extension ext: String) -> URL? {
        let testBundle = Bundle(for: RegistryPathsTests.self)
        if let url = testBundle.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        let candidates = [
            testBundle.resourceURL?.appendingPathComponent("\(name).\(ext)"),
            testBundle.bundleURL.appendingPathComponent("Contents/Resources/\(name).\(ext)"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/\(name).\(ext)"),
        ]
        for url in candidates {
            if let url, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
