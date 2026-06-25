import XCTest
@testable import MacOSCleaner

final class ConfidenceEngineTests: XCTestCase {
    func test_assess_guaranteed_with_critical_evidence() {
        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "TestApp",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "TestApp",
            teamID: "ABC123",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/TestApp.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["TestVendor"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let evidence: Set<Evidence> = [.bundleIDExact, .launchAgent, .teamID, .developerSignature]
        let result = ConfidenceEngine.assess(evidence, identity: identity)
        XCTAssertEqual(result.tier, .guaranteed)
    }

    func test_assess_veryLikely_without_signature() {
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
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let evidence: Set<Evidence> = [.appNameExact, .launchAgent, .container]
        let result = ConfidenceEngine.assess(evidence, identity: identity)
        XCTAssertEqual(result.tier, .veryLikely)
    }

    func test_assess_possible_with_weak_evidence() {
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
            vendorNames: ["TestVendor"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let evidence: Set<Evidence> = [.vendorName]
        let result = ConfidenceEngine.assess(evidence, identity: identity)
        XCTAssertEqual(result.tier, .possible)
    }

    func test_jetBrains_degradation_with_only_vendorName() {
        let identity = AppIdentity(
            bundleID: "com.jetbrains.intellij",
            appName: "IntelliJ IDEA",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "idea",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/IntelliJ IDEA.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["JetBrains"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: true, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let evidence: Set<Evidence> = [.vendorName]
        let result = ConfidenceEngine.assess(evidence, identity: identity)
        // JetBrains degradation: vendorName-only with nonVendorCount=0 < 3 → degrades .possible to .ignore
        XCTAssertEqual(result.tier, .ignore)
    }

    func test_jetBrains_allows_guaranteed_with_sufficient_evidence() {
        let identity = AppIdentity(
            bundleID: "com.jetbrains.intellij",
            appName: "IntelliJ IDEA",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "idea",
            teamID: "JB123",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/IntelliJ IDEA.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["JetBrains"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: true, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let evidence: Set<Evidence> = [.bundleIDExact, .teamID, .launchAgent, .container, .plistContent]
        let result = ConfidenceEngine.assess(evidence, identity: identity)
        XCTAssertEqual(result.tier, .guaranteed)
    }

    func test_ignore_when_no_evidence() {
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
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let result = ConfidenceEngine.assess([], identity: identity)
        XCTAssertEqual(result.tier, .ignore)
    }
}
