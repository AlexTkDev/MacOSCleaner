import XCTest
@testable import MacOSCleaner

final class AppDiscoveryTests: XCTestCase {
    func test_findAll_includesApplicationDirectories() async {
        let discovery = AppDiscovery()
        let urls = await discovery.findAll()
        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls.contains { $0.pathExtension == "app" })
    }
}
