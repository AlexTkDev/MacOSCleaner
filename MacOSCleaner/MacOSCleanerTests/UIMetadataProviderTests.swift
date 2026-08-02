import XCTest
@testable import MacOSCleaner

final class UIMetadataProviderTests: XCTestCase {
    private var provider: UIMetadataProvider {
        // Prefer private catalog via the app host bundle when available.
        UIMetadataProvider(bundle: .main)
    }

    func test_metadata_exactBundleIDLookup() async throws {
        try CatalogTestSupport.requirePrivateCatalog()
        let metadata = await provider.metadata(forBundleID: "com.google.Chrome")
        XCTAssertEqual(metadata?.registryKey, "com.google.Chrome")
        XCTAssertEqual(metadata?.difficulty, .high)
        XCTAssertFalse(metadata?.knownIssues.isEmpty ?? true)
    }

    func test_metadata_prefixFallback() async throws {
        try CatalogTestSupport.requirePrivateCatalog()
        let metadata = await provider.metadata(forBundleID: "com.jetbrains.intellij")
        XCTAssertNotNil(metadata)
        let hasContent = !(metadata?.knownIssues.isEmpty ?? true) || metadata?.parentSuite != nil
        XCTAssertTrue(hasContent)
    }

    func test_metadata_longestPrefixWins() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UIMetadataProviderTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let data = """
        {
          "version": "1",
          "apps": {
            "general": {
              "name": "General",
              "difficulty": "low",
              "known_issues": [],
              "bundle_ids": [],
              "bundle_id_prefixes": ["com.example."],
              "parent_suite": null
            },
            "specific": {
              "name": "Specific",
              "difficulty": "high",
              "known_issues": [],
              "bundle_ids": [],
              "bundle_id_prefixes": ["com.example.app."],
              "parent_suite": null
            }
          }
        }
        """.data(using: .utf8)!
        try data.write(to: url)

        let localProvider = UIMetadataProvider(fileURL: url)
        let metadata = await localProvider.metadata(forBundleID: "com.example.app.beta")
        XCTAssertEqual(metadata?.registryKey, "specific")
        XCTAssertEqual(metadata?.name, "Specific")
    }

    func test_metadata_parentSuite() async throws {
        try CatalogTestSupport.requirePrivateCatalog()
        let metadata = await provider.metadata(forBundleID: "com.google.Chrome.canary")
        XCTAssertEqual(metadata?.parentSuite, "Google Chrome")
    }

    func test_metadata_unknownBundleReturnsNil() async {
        let unknown = await provider.metadata(forBundleID: "unknown.com.foo")
        let empty = await provider.metadata(forBundleID: "")
        XCTAssertNil(unknown)
        XCTAssertNil(empty)
    }

    func test_metadata_missingResourceGraceful() async {
        let missing = UIMetadataProvider(bundle: Bundle(for: UIMetadataProviderTests.self), resourceName: "missing_ui_metadata")
        let metadata = await missing.metadata(forBundleID: "com.google.Chrome")
        XCTAssertNil(metadata)
    }
}
