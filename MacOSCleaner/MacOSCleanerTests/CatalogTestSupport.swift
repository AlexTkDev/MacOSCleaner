import XCTest
@testable import MacOSCleaner

enum CatalogTestSupport {
    static var hasPrivateCatalog: Bool {
        GeneratedCleanupPaths.catalogSource == .privateAsset
    }

    /// Skips when the private asset is absent; fails hard under REQUIRE_PRIVATE_CATALOG=YES.
    static func requirePrivateCatalog(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if hasPrivateCatalog { return }
        if PrivateCatalogStore.requiresPrivateCatalog {
            XCTFail(
                "REQUIRE_PRIVATE_CATALOG=YES but private catalog asset was not loaded",
                file: file,
                line: line
            )
        }
        throw XCTSkip("private catalog asset not available")
    }
}
