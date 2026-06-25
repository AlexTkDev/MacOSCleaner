import XCTest
@testable import MacOSCleaner

final class VerificationEngineTests: XCTestCase {
    var testRoot: URL!
    var mockRunner: MockCommandRunner!
    var plistCache: PlistContentCache!
    var codesignCache: CodesignCache!

    override func setUp() {
        super.setUp()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerificationEngineTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)

        mockRunner = MockCommandRunner()
        plistCache = PlistContentCache()
        codesignCache = CodesignCache()
    }

    override func tearDown() {
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        super.tearDown()
    }

    func testVerify_noLeftovers_returnsZero() async {
        mockRunner.mockMdfind(query: "com.test.nonexistent", results: [])
        mockRunner.mockPkgutil(bundleID: "com.test.nonexistent", files: [])

        let identity = AppIdentity(
            bundleID: "com.test.nonexistent",
            appName: "TestNonexistent",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "TestNonexistent",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/TestNonexistent.app"),
            isAppStore: false,
            isSandboxed: false,
            isAdHocSigned: false,
            vendorNames: [],
            helperNames: [],
            frameworkNames: [],
            xpcServiceNames: [],
            plugInNames: [],
            isElectron: false,
            isJetBrains: false,
            isFlutter: false,
            isJava: false,
            isQt: false,
            isDocker: false
        )

        let engine = VerificationEngine(
            commandRunner: mockRunner,
            codesignCache: codesignCache,
            plistCache: plistCache
        )

        let report = await engine.verify(identity: identity)
        XCTAssertFalse(report.hasLeftovers)
        XCTAssertEqual(report.count, 0)
        XCTAssertTrue(report.leftovers.isEmpty)
    }

    func testVerify_withRealDir_detectsLeftover() async {
        // Create a directory in ~/Library/Application Support/ so CandidateCollector
        // finds it via file system scan (no mdfind mocking needed).
        let appName = "TestApp_\(UUID().uuidString)"
        let supportDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appName)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: supportDir) }

        // The directory name matches identity.appName, so EvidenceProbe will
        // produce .appNameExact (weight 60) which exceeds .veryLikely threshold.
        let identity = AppIdentity(
            bundleID: "com.test.\(appName)",
            appName: appName,
            bundleName: nil,
            bundleVersion: nil,
            executableName: appName,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(appName).app"),
            isAppStore: false,
            isSandboxed: false,
            isAdHocSigned: false,
            vendorNames: [],
            helperNames: [],
            frameworkNames: [],
            xpcServiceNames: [],
            plugInNames: [],
            isElectron: false,
            isJetBrains: false,
            isFlutter: false,
            isJava: false,
            isQt: false,
            isDocker: false
        )

        let engine = VerificationEngine(
            codesignCache: codesignCache,
            plistCache: plistCache
        )

        let report = await engine.verify(identity: identity)
        XCTAssertTrue(report.hasLeftovers, "Should detect leftover directory in ~/Library/Application Support/")
        XCTAssertGreaterThan(report.count, 0)
    }
}
