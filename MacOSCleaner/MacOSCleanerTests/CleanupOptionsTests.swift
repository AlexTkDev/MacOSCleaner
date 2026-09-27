import XCTest
@testable import MacOSCleaner

final class CleanupOptionsTests: XCTestCase {

    func testDefaultOptions() {
        let options = CleanupOptions()
        XCTAssertFalse(options.cleanDSStore)
        XCTAssertTrue(options.cleanMaven)
        XCTAssertTrue(options.cleanModCache)
        XCTAssertTrue(options.cleanProjects)
        XCTAssertFalse(options.cleanProjectArtifacts)
        XCTAssertEqual(options.projectArtifactsOlderThanDays, 60)
    }

    func testAllCategoriesAlwaysIncluded() {
        let options = CleanupOptions()
        let categories = options.categories()

        XCTAssertTrue(categories.contains(.appCaches))
        XCTAssertTrue(categories.contains(.packageManagers))
        XCTAssertTrue(categories.contains(.browserCaches))
        XCTAssertTrue(categories.contains(.messagingMedia))
        XCTAssertTrue(categories.contains(.docker))
        XCTAssertTrue(categories.contains(.userLogs))
        XCTAssertTrue(categories.contains(.systemCaches))
        XCTAssertTrue(categories.contains(.appContainers))
        XCTAssertTrue(categories.contains(.dotfileCaches))
        XCTAssertFalse(categories.contains(.orphanedRemnants))
        XCTAssertFalse(categories.contains(.orphanedFiles))
        XCTAssertFalse(categories.contains(.oldBackups))
        XCTAssertFalse(categories.contains(.aiModels))
        XCTAssertFalse(categories.contains(.installerPackages))
        XCTAssertFalse(categories.contains(.launchAgents))
        XCTAssertFalse(categories.contains(.launchDaemons))
        XCTAssertFalse(categories.contains(.privilegedHelpers))
        XCTAssertFalse(categories.contains(.pkgReceipts))
        XCTAssertFalse(categories.contains(.internetPlugins))
        XCTAssertTrue(categories.contains(.iosBackups))
        XCTAssertTrue(categories.contains(.iosSimulators))
    }

    func testDevCategoriesAlwaysIncluded() {
        let options = CleanupOptions()
        let categories = options.categories()

        XCTAssertTrue(categories.contains(.gradleMaven))
        XCTAssertTrue(categories.contains(.flutterDart))
        XCTAssertTrue(categories.contains(.xcode))
        XCTAssertTrue(categories.contains(.androidCaches))
        XCTAssertTrue(categories.contains(.androidSDK))
        XCTAssertTrue(categories.contains(.ideCaches))
        XCTAssertTrue(categories.contains(.languageCaches))
    }

    func testDynamicCacheDiscoveryIncluded() {
        let options = CleanupOptions()
        let categories = options.categories()

        XCTAssertTrue(categories.contains(.dynamicCacheDiscovery))
    }

    func testTotalCategoryCount() {
        let options = CleanupOptions()
        let categories = options.categories()

        XCTAssertEqual(categories.count, 37)
        XCTAssertFalse(categories.contains(.fontCache))
    }

    func testFontCacheOption() {
        let defaultOptions = CleanupOptions()
        XCTAssertFalse(defaultOptions.cleanFontCache)
        XCTAssertFalse(defaultOptions.categories().contains(.fontCache))

        let fontOptions = CleanupOptions(cleanFontCache: true)
        XCTAssertTrue(fontOptions.cleanFontCache)
        XCTAssertTrue(fontOptions.categories().contains(.fontCache))
    }

    func testDSStoreEnabledAddsScatteredJunk() {
        let options = CleanupOptions(cleanDSStore: true)
        let categories = options.categories()

        XCTAssertTrue(categories.contains(.scatteredJunk))
    }

    func testDSStoreDisabledExcludesScatteredJunk() {
        let options = CleanupOptions(cleanDSStore: false)
        let categories = options.categories()

        XCTAssertFalse(categories.contains(.scatteredJunk))
    }

    func testProjectArtifactsDisabledByDefault() {
        let options = CleanupOptions()
        XCTAssertFalse(options.categories().contains(.projectBuildArtifacts))
    }

    func testProjectArtifactsEnabledAddsCategory() {
        let options = CleanupOptions(cleanProjectArtifacts: true)
        XCTAssertTrue(options.categories().contains(.projectBuildArtifacts))
    }

    func testScanCategoriesAreRunnablePlusReviewOnly() {
        let options = CleanupOptions()
        let scanned = options.scanCategories()
        let expected = options.categories() + CleanupCategory.reviewOnly.filter { !options.categories().contains($0) }
        XCTAssertEqual(scanned, expected)
        XCTAssertFalse(scanned.contains(.launchAgents))
        XCTAssertFalse(scanned.contains(.voiceMemos))
        XCTAssertTrue(scanned.contains(.largeFiles))
        XCTAssertTrue(scanned.contains(.oldBackups))

        var withFont = CleanupOptions(cleanVoiceMemos: true, cleanFontCache: true)
        XCTAssertTrue(withFont.scanCategories().contains(.fontCache))
        XCTAssertTrue(withFont.scanCategories().contains(.voiceMemos))
    }

    func testOptionsEquality() {
        let a = CleanupOptions(cleanDSStore: false)
        let b = CleanupOptions(cleanDSStore: false)
        let c = CleanupOptions(cleanDSStore: true)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
