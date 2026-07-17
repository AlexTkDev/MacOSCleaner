import XCTest
@testable import MacOSCleaner

final class AppDiscoveryTests: XCTestCase {
    func test_findAll_includesApplicationDirectories() async {
        let discovery = AppDiscovery()
        let urls = await discovery.findAll()
        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls.contains { $0.pathExtension == "app" })
    }

    func test_homebrewApplications_findsOnlyTopLevelAppsInReceiptedKegs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        let cellar = root.appendingPathComponent("Cellar", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keg = cellar.appendingPathComponent("python@3.14/3.14.6", isDirectory: true)
        let idle = keg.appendingPathComponent("IDLE 3.app", isDirectory: true)
        let launcher = keg.appendingPathComponent("Python Launcher 3.app", isDirectory: true)
        let nested = keg.appendingPathComponent("lib/Nested.app", isDirectory: true)
        try FileManager.default.createDirectory(at: idle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launcher, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: keg.appendingPathComponent("INSTALL_RECEIPT.json"))

        let unreceipted = cellar.appendingPathComponent("other/1.0/Hidden.app", isDirectory: true)
        try FileManager.default.createDirectory(at: unreceipted, withIntermediateDirectories: true)

        let applications = AppDiscovery.homebrewApplications(in: [cellar])
        XCTAssertEqual(
            Set(applications.map { $0.resolvingSymlinksInPath().path }),
            Set([idle, launcher].map { $0.resolvingSymlinksInPath().path })
        )
    }
}
