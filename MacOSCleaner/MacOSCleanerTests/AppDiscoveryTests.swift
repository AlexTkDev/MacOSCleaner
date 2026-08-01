import XCTest
@testable import MacOSCleaner

final class AppDiscoveryTests: XCTestCase {
    func test_findAll_includesApplicationDirectories() async {
        let discovery = AppDiscovery()
        let urls = await discovery.findAll()
        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls.contains { $0.pathExtension == "app" })
        // SIP / Cryptex apps (e.g. Safari) must not appear.
        XCTAssertFalse(urls.contains { $0.lastPathComponent == "Safari.app" })
        XCTAssertFalse(urls.contains { AppDiscovery.isUndeletableSystemApp($0) })
    }

    func test_isUndeletableSystemApp_rejectsSystemAndCryptex() {
        XCTAssertTrue(
            AppDiscovery.isUndeletableSystemApp(
                URL(fileURLWithPath: "/System/Applications/Calculator.app")
            )
        )
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        if FileManager.default.fileExists(atPath: safari.path) {
            XCTAssertTrue(AppDiscovery.isUndeletableSystemApp(safari))
        }
        XCTAssertFalse(
            AppDiscovery.isUndeletableSystemApp(
                URL(fileURLWithPath: "/Applications/Google Chrome.app")
            )
        )
    }

    func test_isUndeletableSystemApp_rejectsNestedAppleAndDTSatellites() {
        let nested = URL(fileURLWithPath:
            "/Applications/Xcode.app/Contents/Applications/com.apple.dt.ExternalViewService.app")
        // No real bundle on disk — still treat path+ID pattern via top-level check:
        // nested .app count > 1 → not top-level; without bundle ID only nested apple via dt needs Bundle.
        XCTAssertFalse(AppDiscovery.isTopLevelUserApplication(nested.path))

        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")
        XCTAssertTrue(AppDiscovery.isTopLevelUserApplication(xcode.path))
        XCTAssertTrue(AppDiscovery.isTopLevelUserApplication("/Applications/Utilities/Terminal.app"))
        XCTAssertFalse(AppDiscovery.isTopLevelUserApplication(
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app"
        ))
    }

    func test_isListableApplication_requiresAppExtensionAndBundleID() {
        XCTAssertFalse(AppDiscovery.isListableApplication(
            URL(fileURLWithPath: "/usr/local/bin/node")
        ))
        // Synthetic path without Info.plist → no bundle ID → not listable.
        XCTAssertFalse(AppDiscovery.isListableApplication(
            URL(fileURLWithPath: "/tmp/FakeMissingBundle.app")
        ))
    }

    func test_applicationBundles_includesNestedLevel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDiscoveryNested-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let top = root.appendingPathComponent("Top.app", isDirectory: true)
        let utilities = root.appendingPathComponent("Utilities", isDirectory: true)
        let nested = utilities.appendingPathComponent("Nested.app", isDirectory: true)
        try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let found = AppDiscovery.applicationBundles(in: root)
        XCTAssertEqual(
            Set(found.map(\.lastPathComponent)),
            Set(["Top.app", "Nested.app"])
        )
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
