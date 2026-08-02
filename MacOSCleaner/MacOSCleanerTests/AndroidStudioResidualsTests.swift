import XCTest
@testable import MacOSCleaner

final class AndroidStudioResidualsTests: XCTestCase {
    func test_rule_boostsDeveloperPathsToGuaranteedWeight() {
        let rule = AndroidStudioRule()
        let identity = AppIdentity(
            bundleID: "com.google.android.studio",
            appName: "Android Studio",
            bundleName: "Android Studio",
            bundleVersion: "2026.1",
            executableName: "studio",
            teamID: "EQHXZ8M8AV",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Android Studio.app"),
            isAppStore: false,
            isSandboxed: false,
            isAdHocSigned: false,
            vendorNames: ["Google"],
            helperNames: [],
            frameworkNames: [],
            xpcServiceNames: [],
            plugInNames: [],
            appGroups: [],
            isElectron: false,
            isJetBrains: false,
            isFlutter: false,
            isJava: true,
            isQt: false,
            isDocker: false
        )

        let paths = [
            "/Users/alex/Library/Android",
            "/Users/alex/.gradle",
            "/Users/alex/.android",
            "/Users/alex/Library/Android/sdk",
        ]
        for path in paths {
            let score = rule.evidence(for: URL(fileURLWithPath: path), identity: identity)
                .reduce(0) { $0 + $1.weight }
            XCTAssertGreaterThanOrEqual(score, 100, path)
        }
    }

    func test_isAndroidStudioDeveloperPath() {
        XCTAssertTrue(UninstallerService.isAndroidStudioDeveloperPath("/Users/alex/.gradle"))
        XCTAssertTrue(UninstallerService.isAndroidStudioDeveloperPath("/Users/alex/Library/Android"))
        XCTAssertTrue(UninstallerService.isAndroidStudioDeveloperPath("/Users/alex/.android/avd"))
        XCTAssertFalse(UninstallerService.isAndroidStudioDeveloperPath("/Users/alex/Library/Caches/Google"))
    }

    func test_overlapsDeveloperRoot_dedupesRelatedAgainstDeveloperSSOT() {
        let roots = ["/Users/alex/.gradle", "/Users/alex/Library/Android"]
        XCTAssertTrue(UninstallerService.overlapsDeveloperRoot(
            "/Users/alex/.gradle",
            roots: roots
        ))
        XCTAssertTrue(UninstallerService.overlapsDeveloperRoot(
            "/Users/alex/Library/Android/sdk",
            roots: roots
        ))
        XCTAssertFalse(UninstallerService.overlapsDeveloperRoot(
            "/Users/alex/Library/Caches/Google",
            roots: roots
        ))
    }
}
