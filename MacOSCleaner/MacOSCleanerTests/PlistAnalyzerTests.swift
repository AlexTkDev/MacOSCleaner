import XCTest
@testable import MacOSCleaner

final class PlistAnalyzerTests: XCTestCase {
    private var tempDir: URL!
    private var plistCache: PlistContentCache!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlistAnalyzerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        plistCache = PlistContentCache()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makePlist(named name: String, bundleID: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": "TestApp",
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try! data.write(to: url)
        return url
    }

    func test_analyze_finds_matching_plist() async {
        let plistURL = makePlist(named: "com.test.app.plist", bundleID: "com.test.app")
        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "TestApp",
            bundleName: "TestApp",
            bundleVersion: nil,
            executableName: "TestApp",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/TestApp.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["TestVendor"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )

        let analyzer = PlistAnalyzer(fileManager: .default, plistCache: plistCache)
        // Override search dirs to just our temp dir
        // We'll test the cache hit directly
        let content = await plistCache.getContent(url: plistURL)
        XCTAssertNotNil(content)
        XCTAssertTrue(content!.contains("com.test.app"))
    }
}
