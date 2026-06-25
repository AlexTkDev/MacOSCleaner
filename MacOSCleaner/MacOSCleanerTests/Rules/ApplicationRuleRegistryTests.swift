import XCTest
@testable import MacOSCleaner

final class ApplicationRuleRegistryTests: XCTestCase {
    func test_registry_returns_defaultRule_for_unknown_app() async {
        let registry = ApplicationRuleRegistry()
        let identity = AppIdentity(
            bundleID: "com.unknown.app",
            appName: "Unknown",
            bundleName: nil, bundleVersion: nil,
            executableName: "Unknown",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Unknown.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Generic")
    }

    func test_registry_returns_electronRule_for_postman() async {
        let registry = ApplicationRuleRegistry()
        await registry.registerAll([
            ElectronRule(), BrowserRule(), JetBrainsRule(),
            DockerRule(), XcodeRule(), AndroidStudioRule(),
        ])
        let identity = AppIdentity(
            bundleID: "com.postmanlabs.mac",
            appName: "Postman",
            bundleName: nil, bundleVersion: nil,
            executableName: "Postman",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Postman.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Postman"], helperNames: [], frameworkNames: ["Electron Framework"],
            xpcServiceNames: [], plugInNames: [],
            isElectron: true, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Electron")
    }

    func test_registry_returns_jetbrainsRule_for_intellij() async {
        let registry = ApplicationRuleRegistry()
        await registry.registerAll([
            ElectronRule(), BrowserRule(), JetBrainsRule(),
            DockerRule(), XcodeRule(), AndroidStudioRule(),
        ])
        let identity = AppIdentity(
            bundleID: "com.jetbrains.intellij",
            appName: "IntelliJ IDEA",
            bundleName: "IntelliJ IDEA", bundleVersion: nil,
            executableName: "idea",
            teamID: "2YEDZK7QJ8", signingAuthority: "Developer ID Application: JetBrains",
            bundleURL: URL(fileURLWithPath: "/Applications/IntelliJ IDEA.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["JetBrains", "IntelliJ"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: true, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "JetBrains")
    }
}

final class ElectronRuleTests: XCTestCase {
    func test_matches_postman() {
        let rule = ElectronRule()
        let identity = AppIdentity(
            bundleID: "com.postmanlabs.mac",
            appName: "Postman",
            bundleName: nil, bundleVersion: nil,
            executableName: "Postman",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Postman.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: ["Electron Framework"],
            xpcServiceNames: [], plugInNames: [],
            isElectron: true, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_evidence_for_electron_cache() {
        let rule = ElectronRule()
        let identity = AppIdentity(
            bundleID: "com.postmanlabs.mac",
            appName: "Postman",
            bundleName: nil, bundleVersion: nil,
            executableName: "Postman",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Postman.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: true, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Postman/Cache")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }
}

final class BrowserRuleTests: XCTestCase {
    func test_matches_chrome() {
        let rule = BrowserRule()
        let identity = AppIdentity(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            bundleName: nil, bundleVersion: nil,
            executableName: "Google Chrome",
            teamID: "EQHXZ8M8AV", signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Google"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_evidence_for_chrome_cache() {
        let rule = BrowserRule()
        let identity = AppIdentity(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            bundleName: nil, bundleVersion: nil,
            executableName: "Google Chrome",
            teamID: "EQHXZ8M8AV", signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/Google Chrome/Default/Cache")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .appName })
    }
}

final class DockerRuleTests: XCTestCase {
    func test_matches_docker() {
        let rule = DockerRule()
        let identity = AppIdentity(
            bundleID: "com.docker.docker",
            appName: "Docker",
            bundleName: nil, bundleVersion: nil,
            executableName: "Docker",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Docker.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Docker"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: true
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_evidence_for_docker_container() {
        let rule = DockerRule()
        let identity = AppIdentity(
            bundleID: "com.docker.docker",
            appName: "Docker",
            bundleName: nil, bundleVersion: nil,
            executableName: "Docker",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Docker.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: true
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Containers/com.docker.docker")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .bundleID })
    }
}

final class JetBrainsRuleTests: XCTestCase {
    func test_matches_intellij() {
        let rule = JetBrainsRule()
        let identity = AppIdentity(
            bundleID: "com.jetbrains.intellij",
            appName: "IntelliJ IDEA",
            bundleName: nil, bundleVersion: nil,
            executableName: "idea",
            teamID: "2YEDZK7QJ8", signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/IntelliJ IDEA.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["JetBrains"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: true, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_does_not_match_non_jetbrains() {
        let rule = JetBrainsRule()
        let identity = AppIdentity(
            bundleID: "com.postmanlabs.mac",
            appName: "Postman",
            bundleName: nil, bundleVersion: nil,
            executableName: "Postman",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Postman.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }
}

final class XcodeRuleTests: XCTestCase {
    func test_matches_xcode() {
        let rule = XcodeRule()
        let identity = AppIdentity(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            bundleName: nil, bundleVersion: nil,
            executableName: "Xcode",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_evidence_for_xcode_container() {
        let rule = XcodeRule()
        let identity = AppIdentity(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            bundleName: nil, bundleVersion: nil,
            executableName: "Xcode",
            teamID: nil, signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Containers/com.apple.dt.Xcode")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .bundleID })
    }
}

final class AndroidStudioRuleTests: XCTestCase {
    func test_matches_android_studio() {
        let rule = AndroidStudioRule()
        let identity = AppIdentity(
            bundleID: "com.google.android.studio",
            appName: "Android Studio",
            bundleName: nil, bundleVersion: nil,
            executableName: "studio",
            teamID: "EQHXZ8M8AV", signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Android Studio.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Google"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }
}
