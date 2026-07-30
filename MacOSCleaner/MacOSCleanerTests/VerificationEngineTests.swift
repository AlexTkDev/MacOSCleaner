import XCTest
@testable import MacOSCleaner

final class VerificationEngineTests: XCTestCase {
    var fileSystemContext: FileSystemContext!
    var testRoot: URL!
    var mockRunner: MockCommandRunner!
    var plistCache: PlistContentCache!
    var codesignCache: CodesignCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        testRoot = fileSystemContext.homeDirectory
        mockRunner = MockCommandRunner()
        plistCache = PlistContentCache()
        codesignCache = CodesignCache()
    }

    override func tearDownWithError() throws {
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        testRoot = nil
        try super.tearDownWithError()
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
            plistCache: plistCache,
            fileSystemContext: fileSystemContext
        )

        let report = await engine.verify(identity: identity)
        XCTAssertFalse(report.hasLeftovers)
        XCTAssertEqual(report.count, 0)
        XCTAssertTrue(report.leftovers.isEmpty)
    }

    func testVerify_withIsolatedDir_detectsLeftover() async throws {
        let appName = "TestApp_\(UUID().uuidString)"
        let supportDir = testRoot
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: supportDir.appendingPathComponent("marker.dat"))

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
            commandRunner: mockRunner,
            codesignCache: codesignCache,
            plistCache: plistCache,
            fileSystemContext: fileSystemContext
        )

        let report = await engine.verify(identity: identity)
        XCTAssertTrue(report.hasLeftovers, "Should detect leftover under isolated Application Support")
        XCTAssertGreaterThan(report.count, 0)
    }
}
