import XCTest
@testable import MacOSCleaner

final class KnownResidualCatalogTests: XCTestCase {

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

    func test_chromeHasCatalogTemplates() {
        let templates = KnownResidualCatalog.pathTemplates(bundleID: "com.google.Chrome")
        XCTAssertFalse(templates.isEmpty)
        XCTAssertTrue(templates.contains { $0.contains("Application Support/Google/Chrome") })
        XCTAssertTrue(templates.contains { $0.contains("Library/Caches") })
        XCTAssertFalse(templates.contains { $0.lowercased().contains("keystone") })
        XCTAssertFalse(templates.contains { $0.lowercased().contains("googlesoftwareupdate") })
    }

    func test_dockerHasCatalogTemplates() {
        let templates = KnownResidualCatalog.pathTemplates(bundleID: "com.docker.docker")
        XCTAssertFalse(templates.isEmpty)
        XCTAssertTrue(templates.contains { $0.contains("group.com.docker") || $0.contains("com.docker.docker") })
        XCTAssertFalse(templates.contains { $0 == "~/.docker" || $0.hasPrefix("~/.docker/") })
    }

    func test_jetbrainsPrefixMatchesFamily() {
        let templates = KnownResidualCatalog.pathTemplates(bundleID: "com.jetbrains.intellij")
        XCTAssertFalse(templates.isEmpty)
        XCTAssertTrue(templates.contains { $0.contains("JetBrains") })
    }

    func test_safariExcludedFromCatalog() {
        XCTAssertTrue(KnownResidualCatalog.pathTemplates(bundleID: "com.apple.Safari").isEmpty)
    }

    func test_unknownBundleReturnsEmpty() {
        XCTAssertTrue(KnownResidualCatalog.pathTemplates(bundleID: "unknown.com.foo").isEmpty)
        XCTAssertTrue(KnownResidualCatalog.pathTemplates(bundleID: "").isEmpty)
    }

    func test_expandFindsExistingExactPath() throws {
        let home = NSTemporaryDirectory() + "KnownResidualCatalogTests-\(UUID().uuidString)"
        let target = home + "/Library/Caches/com.google.Chrome"
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }

        let found = KnownResidualCatalog.expand(
            template: "~/Library/Caches/com.google.Chrome",
            home: home
        )
        XCTAssertEqual(found, [target])
    }

    func test_collectorIncludesCatalogPath() async throws {
        let home = NSHomeDirectory()
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

        let collection = await CandidateCollector().collectDetailed(
            identity: identity(bundleID: "com.google.Chrome", appName: "Google Chrome", vendorNames: ["Google"]),
            mode: .safe
        )
        XCTAssertTrue(
            collection.catalogPaths.contains { $0.path == cachePath },
            "Catalog must surface ~/Library/Caches/com.google.Chrome"
        )
        XCTAssertTrue(collection.candidates.contains { $0.path == cachePath })
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
        let generated = GeneratedCleanupPaths.browserCaches.map(\.path)
        XCTAssertFalse(generated.isEmpty)
        for g in generated.prefix(5) {
            XCTAssertTrue(paths.contains(g), "Missing merged path \(g)")
        }
    }
}
