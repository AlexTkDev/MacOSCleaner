import XCTest
@testable import MacOSCleaner

final class CleanupOptionsTests: XCTestCase {

    func testDefaultOptions() {
        let options = CleanupOptions()
        XCTAssertFalse(options.cleanDSStore)
        XCTAssertTrue(options.cleanMaven)
        XCTAssertTrue(options.cleanModCache)
        XCTAssertTrue(options.cleanProjects)
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
        XCTAssertTrue(categories.contains(.orphanedRemnants))
        XCTAssertTrue(categories.contains(.orphanedFiles))
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

        XCTAssertEqual(categories.count, 21)
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

    func testOptionsEquality() {
        let a = CleanupOptions(cleanDSStore: false)
        let b = CleanupOptions(cleanDSStore: false)
        let c = CleanupOptions(cleanDSStore: true)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
