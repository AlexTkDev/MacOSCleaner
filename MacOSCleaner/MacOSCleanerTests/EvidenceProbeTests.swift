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

    func test_probe_appName_caseInsensitive() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        let identity = AppIdentity(
            bundleID: "com.hnc.Discord",
            appName: "Discord",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Discord",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Discord.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: true, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        // Electron apps often use lowercase data dirs
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/discord")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.appNameExact))
    }

    func test_probe_launchAgent_shortName_noSubstringFalsePositive() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        let identity = AppIdentity(
            bundleID: "company.thebrowser.Browser",
            appName: "Arc",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Arc",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Arc.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        // "seARChmarquis" contains "arc" mid-word — must NOT match
        let foreign = URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/com.searchmarquis.plist")
        let foreignEvidence = await probe.probe(url: foreign, identity: identity)
        XCTAssertFalse(foreignEvidence.contains(Evidence.launchAgent))

        // "ArcUpdater" starts a token with "arc" — must match
        let own = URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/ArcUpdater.plist")
        let ownEvidence = await probe.probe(url: own, identity: identity)
        XCTAssertTrue(ownEvidence.contains(Evidence.launchAgent))
    }

    func test_probe_groupContainer_teamIDPrefix_weakEvidence() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        let identity = AppIdentity(
            bundleID: "com.microsoft.word",
            appName: "Microsoft Word",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Microsoft Word",
            teamID: "UBF8T346G9",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Microsoft Word.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Group Containers/UBF8T346G9.Office")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.vendorName))
        XCTAssertFalse(evidence.contains(Evidence.appGroup))
    }

    func test_probe_groupContainer_teamIDWithBundleID_strongEvidence() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        let identity = AppIdentity(
            bundleID: "dev.orbstack",
            appName: "OrbStack",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "OrbStack",
            teamID: "HUAQ24HBR6",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/OrbStack.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: true
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Group Containers/HUAQ24HBR6.dev.orbstack")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.appGroup))
    }

    func test_probe_groupContainer_entitlementAppGroup_strongEvidence() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        // AdGuard VPN (com.adguard.mac.vpn) declares TC3Q7MAJXF.com.adguard.mac
        // in its entitlements — no bundle-ID suffix relation, entitlements only.
        var identity = AppIdentity(
            bundleID: "com.adguard.mac.vpn",
            appName: "AdGuard VPN",
            bundleName: "AdGuard VPN",
            bundleVersion: nil,
            executableName: "AdGuard VPN",
            teamID: "TC3Q7MAJXF",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/AdGuard VPN.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        identity.appGroups = ["TC3Q7MAJXF.com.adguard.mac"]
        let url = URL(fileURLWithPath: "/Users/test/Library/Group Containers/TC3Q7MAJXF.com.adguard.mac")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.appGroup))
    }

    func test_probe_foreignContainerDesktop_noEvidence() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        // ai.opencode.desktop must not claim Data/Desktop inside Apple containers
        let identity = AppIdentity(
            bundleID: "ai.opencode.desktop",
            appName: "OpenCode",
            bundleName: "OpenCode",
            bundleVersion: nil,
            executableName: "OpenCode",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/OpenCode.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["OpenCode", "opencode", "Opencode"],
            helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Containers/com.apple.podcasts/Data/Desktop")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.isEmpty, "Foreign container Desktop symlink got \(evidence)")
    }

    func test_probe_bundleName_matchesOnlyInBaseDirContext() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        // iTerm.app declares CFBundleName "iTerm2"; data dir is AS/iTerm2
        let identity = AppIdentity(
            bundleID: "com.googlecode.iterm2",
            appName: "iTerm",
            bundleName: "iTerm2",
            bundleVersion: nil,
            executableName: "iTerm",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/iTerm.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let own = URL(fileURLWithPath: "/Users/test/Library/Application Support/iTerm2")
        let ownEvidence = await probe.probe(url: own, identity: identity)
        XCTAssertTrue(ownEvidence.contains(Evidence.appNameExact))

        // Same name deep inside another app's folder — no identity evidence
        let foreign = URL(fileURLWithPath: "/Users/test/Library/Application Support/OtherApp/Data/iTerm2")
        let foreignEvidence = await probe.probe(url: foreign, identity: identity)
        XCTAssertFalse(foreignEvidence.contains(Evidence.appNameExact))
    }

    func test_probe_cacheFolder_bundleIDExact() async {
        let probe = EvidenceProbe(codesignCache: CodesignCache(), plistCache: PlistContentCache())
        let identity = AppIdentity(
            bundleID: "com.microsoft.autoupdate2",
            appName: "Microsoft AutoUpdate",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Microsoft AutoUpdate",
            teamID: "UBF8T346G9",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Microsoft"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/com.microsoft.autoupdate2")
        let evidence = await probe.probe(url: url, identity: identity)
        XCTAssertTrue(evidence.contains(Evidence.bundleIDExact))
    }

    func test_tokenPrefixMatch() {
        XCTAssertTrue(EvidenceProbe.tokenPrefixMatch("arcupdater.plist", "arc"))
        XCTAssertTrue(EvidenceProbe.tokenPrefixMatch("com.arc.helper", "arc"))
        XCTAssertFalse(EvidenceProbe.tokenPrefixMatch("com.searchmarquis.plist", "arc"))
        XCTAssertFalse(EvidenceProbe.tokenPrefixMatch("monarch", "arc"))
    }

    func test_wordBoundaryMatch() {
        XCTAssertTrue(EvidenceProbe.wordBoundaryMatch("/applications/arc.app/contents", "arc"))
        XCTAssertTrue(EvidenceProbe.wordBoundaryMatch("open arc now", "arc"))
        XCTAssertFalse(EvidenceProbe.wordBoundaryMatch("architecture", "arc"))
        XCTAssertFalse(EvidenceProbe.wordBoundaryMatch("searchmarquis", "arc"))
    }

    func test_probe_appBundle_readsExactBundleIdentifier() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvidenceProbeTests-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("Another Copy.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "org.python.IDLE",
            "CFBundleName": "IDLE",
            "CFBundleExecutable": "IDLE",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        let identity = AppIdentity(
            bundleID: "org.python.IDLE",
            appName: "IDLE 3",
            bundleName: "IDLE",
            bundleVersion: "3.14.6",
            executableName: "IDLE",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/opt/homebrew/Cellar/python@3.14/3.14.6/IDLE 3.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: true,
            vendorNames: ["python"], helperNames: [], frameworkNames: [],
            xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let runner = MockCommandRunner()
        runner.runDelay = .zero
        let evidence = await EvidenceProbe(
            commandRunner: runner,
            codesignCache: CodesignCache(),
            plistCache: PlistContentCache()
        ).probe(url: app, identity: identity)
        XCTAssertTrue(evidence.contains(.bundleIDExact))
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
