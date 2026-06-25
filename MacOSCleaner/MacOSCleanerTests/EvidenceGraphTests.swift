import XCTest
@testable import MacOSCleaner

final class EvidenceGraphTests: XCTestCase {
    func test_init_createsSeedNode() async {
        let identity = AppIdentity(
            bundleID: "com.test.app",
            appName: "Test",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Test",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
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
        let graph = EvidenceGraph(identity: identity)
        let node = await graph.node(for: identity.bundleURL)
        XCTAssertNotNil(node)
        XCTAssertTrue(node?.evidence.contains(.bundleIDExact) == true)
    }

    func test_record_addsEvidence() async {
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
        let graph = EvidenceGraph(identity: identity)
        let cacheURL = URL(fileURLWithPath: "/Library/Caches/test.cache")
        await graph.record(.plistContent, for: cacheURL)
        let node = await graph.node(for: cacheURL)
        XCTAssertNotNil(node)
        XCTAssertTrue(node?.evidence.contains(.plistContent) == true)
    }

    func test_count_returnsNodeCount() async {
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
        let graph = EvidenceGraph(identity: identity)
        await graph.record(.plistContent, for: URL(fileURLWithPath: "/Library/Caches/a.plist"))
        await graph.record(.launchAgent, for: URL(fileURLWithPath: "/Library/LaunchAgents/test.plist"))
        let count = await graph.count()
        XCTAssertEqual(count, 3)
    }

    func test_attach_linksParentToChild() async {
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
        let graph = EvidenceGraph(identity: identity)
        let parent = URL(fileURLWithPath: "/Library/Application Support/Test")
        let child = URL(fileURLWithPath: "/Library/Application Support/Test/sub")
        await graph.attach(child, to: parent, via: .parentDirectory)

        let parentNode = await graph.node(for: parent)
        let childNode = await graph.node(for: child)

        XCTAssertTrue(parentNode?.children.contains(child) == true)
        XCTAssertTrue(childNode?.parents.contains(parent) == true)
        XCTAssertTrue(childNode?.evidence.contains(.parentDirectory) == true)
    }

    func test_allURLs_returnsAllKeys() async {
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
        let graph = EvidenceGraph(identity: identity)
        let other = URL(fileURLWithPath: "/Library/Caches/test.cache")
        await graph.record(.plistContent, for: other)
        let urls = await graph.allURLs()
        XCTAssertTrue(urls.contains(identity.bundleURL))
        XCTAssertTrue(urls.contains(other))
    }
}
