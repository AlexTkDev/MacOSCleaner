import XCTest
@testable import MacOSCleaner

final class ForeignDeveloperTreeTests: XCTestCase {
    func test_xcodeRejectsAndroidSDKPaths() {
        let identity = makeIdentity(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode"
        )
        let rst = URL(fileURLWithPath:
            "/Users/alex/Library/Android/sdk/cmake/3.22.1/share/cmake-3.22/Help/generator/Xcode.rst")
        XCTAssertTrue(CandidateCollector.isForeignDeveloperTree(rst, identity: identity))
        XCTAssertFalse(CandidateCollector.isForeignDeveloperTree(
            URL(fileURLWithPath: "/Users/alex/Library/Caches/com.apple.dt.Xcode"),
            identity: identity
        ))
    }

    func test_androidStudioRejectsXcodeDeveloperTrees() {
        let identity = makeIdentity(
            bundleID: "com.google.android.studio",
            appName: "Android Studio"
        )
        XCTAssertTrue(CandidateCollector.isForeignDeveloperTree(
            URL(fileURLWithPath: "/Users/alex/Library/Developer/Xcode/DerivedData/Foo"),
            identity: identity
        ))
        XCTAssertFalse(CandidateCollector.isForeignDeveloperTree(
            URL(fileURLWithPath: "/Users/alex/Library/Android/sdk"),
            identity: identity
        ))
    }

    private func makeIdentity(bundleID: String, appName: String) -> AppIdentity {
        AppIdentity(
            bundleID: bundleID,
            appName: appName,
            bundleName: appName,
            bundleVersion: "1",
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
            appGroups: [],
            isElectron: false,
            isJetBrains: false,
            isFlutter: false,
            isJava: false,
            isQt: false,
            isDocker: false
        )
    }
}
