import XCTest
@testable import MacOSCleaner

final class CandidateCollectorTests: XCTestCase {
    func test_collect_returnsURLs() async {
        let collector = CandidateCollector()
        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "TestApp",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "TestApp",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/TestApp.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["TestVendor"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertFalse(candidates.isEmpty)
    }
}
