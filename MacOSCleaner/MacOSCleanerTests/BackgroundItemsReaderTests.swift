import XCTest
@testable import MacOSCleaner

final class BackgroundItemsReaderTests: XCTestCase {
    func test_readLaunchAgents_returnsPlistFiles() async {
        let reader = BackgroundItemsReader()
        let urls = await reader.readLaunchAgents()
        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls.allSatisfy { $0.pathExtension == "plist" })
    }
}
