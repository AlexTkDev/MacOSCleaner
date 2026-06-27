import XCTest
@testable import MacOSCleaner

final class EvidenceProbeTests: XCTestCase {
    func test_probe_bundleIDExact() async {
        let codesignCache = CodesignCache()
        let plistCache = PlistContentCache()
        let probe = EvidenceProbe(codesignCache: codesignCache, plistCache: plistCache)

        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "Test",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Test",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Library/Application Support/com.test.app")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.bundleIDExact))
    }

    func test_probe_launchAgent() async {
        let codesignCache = CodesignCache()
        let plistCache = PlistContentCache()
        let probe = EvidenceProbe(codesignCache: codesignCache, plistCache: plistCache)

        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "Test",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Test",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/com.test.app.plist")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.launchAgent))
    }

    func test_probe_container() async {
        let codesignCache = CodesignCache()
        let plistCache = PlistContentCache()
        let probe = EvidenceProbe(codesignCache: codesignCache, plistCache: plistCache)

        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "Test",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Test",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Containers/com.test.app")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.container))
    }

    func test_probe_appGroup() async {
        let codesignCache = CodesignCache()
        let plistCache = PlistContentCache()
        let probe = EvidenceProbe(codesignCache: codesignCache, plistCache: plistCache)

        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "Test",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Test",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Group Containers/group.com.test.app")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.appGroup))
    }

    func test_probe_noEvidence() async {
        let codesignCache = CodesignCache()
        let plistCache = PlistContentCache()
        let probe = EvidenceProbe(codesignCache: codesignCache, plistCache: plistCache)

        let identity = AppIdentity(
            bundleID: "com.other.app",
            appName: "Other",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Other",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Other.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/tmp/unrelated_file.txt")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.isEmpty)
    }
}
