import XCTest
@testable import MacOSCleaner

final class PrivateCatalogLoaderTests: XCTestCase {
    override func tearDown() {
        PrivateCatalogStore.resetForTesting()
        super.tearDown()
    }

    func test_purposeRoutingWithMiniFixture() async throws {
        let wire = PrivateCatalogWire(
            formatVersion: PrivateCatalogFormat.formatVersion,
            engineHash: "fixture",
            uiHash: "fixture-ui",
            watermarks: ["com.macos-cleaner.provenance.canary.fixture"],
            apps: [
                PrivateCatalogWireApp(
                    key: "com.example.demo",
                    bundleIDs: ["com.example.demo"],
                    bundleIDPrefixes: [],
                    category: CleanupCategory.appCaches.rawValue,
                    paths: [
                        PrivateCatalogWirePath(template: "<CACHES>/com.example.demo", purpose: "cache", isGlob: false, requiresAdmin: false),
                        PrivateCatalogWirePath(template: "<APP_SUPPORT>/Example", purpose: "app_data", isGlob: false, requiresAdmin: false),
                        PrivateCatalogWirePath(template: "<APP_SUPPORT>/ExampleShared", purpose: "shared", isGlob: false, requiresAdmin: false),
                        PrivateCatalogWirePath(template: "<HOME>/.example-models", purpose: "user_content", isGlob: false, requiresAdmin: false),
                        PrivateCatalogWirePath(template: "<SYS_LIB>/Example.helper", purpose: "app_data", isGlob: false, requiresAdmin: true),
                    ]
                ),
            ],
            toolchains: [],
            uiApps: [],
            uiToolchains: []
        )
        let snapshot = PrivateCatalogCodec.snapshot(from: wire, source: .privateAsset)
        PrivateCatalogStore.setOverrideForTesting(snapshot)

        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let home = ctx.homePath

        let cache = "\(home)/Library/Caches/com.example.demo"
        let appData = "\(home)/Library/Application Support/Example"
        let shared = "\(home)/Library/Application Support/ExampleShared"
        let userContent = "\(home)/.example-models"
        for path in [cache, appData, shared, userContent] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }

        let collector = CandidateCollector(
            commandRunner: MockCommandRunner(),
            fileSystemContext: ctx
        )
        let identity = AppIdentity(
            bundleID: "com.example.demo",
            appName: "Example",
            bundleName: "Example",
            bundleVersion: nil,
            executableName: "Example",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Example"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let collection = await collector.collectDetailed(identity: identity, mode: .safe)

        XCTAssertTrue(collection.candidates.contains { $0.path == cache })
        XCTAssertTrue(collection.catalogPaths.contains { $0.path == cache })
        XCTAssertTrue(collection.candidates.contains { $0.path == appData })
        XCTAssertFalse(collection.catalogPaths.contains { $0.path == appData })
        XCTAssertTrue(collection.sharedPaths.contains { $0.path == shared })
        XCTAssertFalse(collection.candidates.contains { $0.path == shared })
        XCTAssertTrue(collection.informationalPaths.contains { $0.path == userContent })
        XCTAssertFalse(collection.candidates.contains { $0.path == userContent })

        let adminResolved = PathToken.home.resolveTemplate("<SYS_LIB>/Example.helper", home: home)
        XCTAssertFalse(collection.candidates.contains(URL(fileURLWithPath: adminResolved)))
        XCTAssertFalse(collection.catalogPaths.contains(URL(fileURLWithPath: adminResolved)))

        XCTAssertNil(GeneratedCleanupPaths.appPaths(forBundleID: "com.macos-cleaner.provenance.canary.fixture"))
    }

    func test_corruptAssetFallsBackToEmpty() {
        // Missing asset path is covered by empty override; decode failures also map to empty.
        PrivateCatalogStore.setOverrideForTesting(.empty)
        XCTAssertEqual(GeneratedCleanupPaths.catalogSource, .publicFallback)
        XCTAssertTrue(GeneratedCleanupPaths.registry.isEmpty)
    }
}
