import XCTest
@testable import MacOSCleaner

final class AppIdentityTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIdentityTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeAppBundle(named name: String, bundleID: String) -> URL {
        let appURL = tempDir.appendingPathComponent("\(name).app")
        let contentsDir = appURL.appendingPathComponent("Contents")
        try? FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundleShortVersionString": "1.0.0",
        ]
        let plistData = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try! plistData.write(to: contentsDir.appendingPathComponent("Info.plist"))
        return appURL
    }

    func test_resolve_postman_identity() async {
        let appURL = makeAppBundle(named: "Postman", bundleID: "com.postmanlabs.mac")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertEqual(identity.appName, "Postman")
        XCTAssertEqual(identity.bundleID, "com.postmanlabs.mac")
    }

    func test_resolve_intellij_identity() async {
        let appURL = makeAppBundle(named: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertEqual(identity.appName, "IntelliJ IDEA")
        XCTAssertEqual(identity.bundleID, "com.jetbrains.intellij")
    }

    func test_resolve_discord_identity() async {
        let appURL = makeAppBundle(named: "Discord", bundleID: "com.hnc.Discord")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertEqual(identity.appName, "Discord")
        XCTAssertEqual(identity.bundleID, "com.hnc.Discord")
    }

    func test_resolve_docker_identity() async {
        let appURL = makeAppBundle(named: "Docker", bundleID: "com.docker.docker")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertEqual(identity.appName, "Docker")
        XCTAssertEqual(identity.bundleID, "com.docker.docker")
    }

    func test_resolve_postman_includes_bundleName_and_version() async {
        let appURL = makeAppBundle(named: "Postman", bundleID: "com.postmanlabs.mac")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertEqual(identity.bundleName, "Postman")
        XCTAssertEqual(identity.bundleVersion, "1.0.0")
    }

    func test_resolve_vendorNames_excludeProductToken() async {
        // Product token "desktop" from ai.opencode.desktop must not become a vendor name
        let appURL = makeAppBundle(named: "OpenCode", bundleID: "ai.opencode.desktop")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertFalse(identity.vendorNames.contains { $0.lowercased() == "desktop" })
        XCTAssertTrue(identity.vendorNames.contains { $0.lowercased() == "opencode" })
    }

    func test_resolve_appGroups_empty_whenUnsigned() async {
        let appURL = makeAppBundle(named: "PlainApp", bundleID: "com.plain.app")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertTrue(identity.appGroups.isEmpty)
    }

    func test_resolve_teamID_isNil_whenUnsigned() async {
        let appURL = makeAppBundle(named: "UnsignedApp", bundleID: "com.unsigned.app")
        let identity = await AppIdentity.resolve(from: appURL)
        XCTAssertNil(identity.teamID)
    }
}
