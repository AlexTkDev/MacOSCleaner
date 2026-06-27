import XCTest
@testable import MacOSCleaner

final class ProblematicAppsTests: XCTestCase {

    // MARK: - Rule Matching Tests

    func test_adobeRule_matches_creativeCloud() {
        let rule = AdobeRule()
        let identity = makeIdentity(
            bundleID: "com.adobe.ccx.process",
            appName: "Adobe Creative Cloud",
            teamID: "JQ5W7278T3"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_adobeRule_matches_photoshop() {
        let rule = AdobeRule()
        let identity = makeIdentity(
            bundleID: "com.adobe.Photoshop",
            appName: "Adobe Photoshop",
            teamID: "JQ5W7278T3"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_adobeRule_matches_byNamePrefix() {
        let rule = AdobeRule()
        let identity = makeIdentity(
            bundleID: "com.unknown.adobe.app",
            appName: "Adobe Something"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_adobeRule_doesNotMatch_unrelated() {
        let rule = AdobeRule()
        let identity = makeIdentity(
            bundleID: "com.apple.Safari",
            appName: "Safari"
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }

    func test_adobeRule_evidence_forApplicationSupport() {
        let rule = AdobeRule()
        let identity = makeIdentity(bundleID: "com.adobe.Photoshop", appName: "Adobe Photoshop")
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Adobe/Photoshop")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .appName })
    }

    func test_adobeRule_evidence_forLaunchDaemon() {
        let rule = AdobeRule()
        let identity = makeIdentity(bundleID: "com.adobe.ccx.process", appName: "Adobe Creative Cloud")
        let url = URL(fileURLWithPath: "/Library/LaunchDaemons/com.adobe.installer.clean.plist")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .bundleID })
    }

    func test_microsoftOfficeRule_matches_word() {
        let rule = MicrosoftOfficeRule()
        let identity = makeIdentity(
            bundleID: "com.microsoft.word",
            appName: "Microsoft Word",
            teamID: "UBF8T346G9"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_microsoftOfficeRule_matches_teams() {
        let rule = MicrosoftOfficeRule()
        let identity = makeIdentity(
            bundleID: "com.microsoft.teams",
            appName: "Microsoft Teams",
            teamID: "UBF8T346G9"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_microsoftOfficeRule_matches_byTeamID() {
        let rule = MicrosoftOfficeRule()
        let identity = makeIdentity(
            bundleID: "com.microsoft.custom",
            appName: "Microsoft Something",
            teamID: "UBF8T346G9"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_microsoftOfficeRule_doesNotMatch_nonMS() {
        let rule = MicrosoftOfficeRule()
        let identity = makeIdentity(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome"
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }

    func test_microsoftOfficeRule_evidence_forGroupContainer() {
        let rule = MicrosoftOfficeRule()
        let identity = makeIdentity(bundleID: "com.microsoft.word", appName: "Microsoft Word")
        let url = URL(fileURLWithPath: "/Users/test/Library/Group Containers/UBF8T346G9.Office")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .bundleID })
    }

    func test_microsoftOfficeRule_evidence_forMAU() {
        let rule = MicrosoftOfficeRule()
        let identity = makeIdentity(bundleID: "com.microsoft.word", appName: "Microsoft Word")
        let url = URL(fileURLWithPath: "/Library/Application Support/Microsoft/MAU2.0")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_steamRule_matches() {
        let rule = SteamRule()
        let identity = makeIdentity(
            bundleID: "com.valvesoftware.steam",
            appName: "Steam",
            teamID: "MXG3986M2V"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_steamRule_doesNotMatch_epic() {
        let rule = SteamRule()
        let identity = makeIdentity(
            bundleID: "com.epicgames.EpicGamesLauncher",
            appName: "Epic Games Launcher"
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }

    func test_steamRule_evidence_forSteamApps() {
        let rule = SteamRule()
        let identity = makeIdentity(bundleID: "com.valvesoftware.steam", appName: "Steam")
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Steam/steamapps")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_steamRule_evidence_forCompatData() {
        let rule = SteamRule()
        let identity = makeIdentity(bundleID: "com.valvesoftware.steam", appName: "Steam")
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Steam/steamapps/compatdata/12345")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_epicGamesRule_matches() {
        let rule = EpicGamesRule()
        let identity = makeIdentity(
            bundleID: "com.epicgames.EpicGamesLauncher",
            appName: "Epic Games Launcher",
            teamID: "95JQ5223G6"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_epicGamesRule_doesNotMatch_steam() {
        let rule = EpicGamesRule()
        let identity = makeIdentity(
            bundleID: "com.valvesoftware.steam",
            appName: "Steam"
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }

    func test_epicGamesRule_evidence_forVaultCache() {
        let rule = EpicGamesRule()
        let identity = makeIdentity(bundleID: "com.epicgames.EpicGamesLauncher", appName: "Epic Games Launcher")
        let url = URL(fileURLWithPath: "/Users/test/Library/Application Support/Epic/VaultCache")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_unityRule_matches() {
        let rule = UnityRule()
        let identity = makeIdentity(
            bundleID: "com.unity3d.unityhub",
            appName: "Unity Hub",
            teamID: "7S365J7V36"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_unityRule_doesNotMatch_unrelated() {
        let rule = UnityRule()
        let identity = makeIdentity(
            bundleID: "com.epicgames.EpicGamesLauncher",
            appName: "Epic Games Launcher"
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }

    func test_unityRule_evidence_forPackageCache() {
        let rule = UnityRule()
        let identity = makeIdentity(bundleID: "com.unity3d.unityhub", appName: "Unity Hub")
        let url = URL(fileURLWithPath: "/Users/test/Library/Unity/PackageCache")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_homebrewRule_matches() {
        let rule = HomebrewRule()
        let identity = makeIdentity(
            bundleID: "N/A (CLI tool)",
            appName: "Homebrew"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_homebrewRule_doesNotMatch() {
        let rule = HomebrewRule()
        let identity = makeIdentity(
            bundleID: "com.apple.Safari",
            appName: "Safari"
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }

    func test_homebrewRule_evidence_forOptHomebrew() {
        let rule = HomebrewRule()
        let identity = makeIdentity(bundleID: "N/A (CLI tool)", appName: "Homebrew")
        let url = URL(fileURLWithPath: "/opt/homebrew")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_homebrewRule_evidence_forCaskroom() {
        let rule = HomebrewRule()
        let identity = makeIdentity(bundleID: "N/A (CLI tool)", appName: "Homebrew")
        let url = URL(fileURLWithPath: "/opt/homebrew/Caskroom/firefox")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_networkExtensionRule_matches_littleSnitch() {
        let rule = NetworkExtensionRule()
        let identity = makeIdentity(
            bundleID: "at.obdev.littlesnitch",
            appName: "Little Snitch"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_networkExtensionRule_matches_nordVPN() {
        let rule = NetworkExtensionRule()
        let identity = makeIdentity(
            bundleID: "com.nordvpn.macos",
            appName: "NordVPN"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_networkExtensionRule_matches_byNameContains() {
        let rule = NetworkExtensionRule()
        let identity = makeIdentity(
            bundleID: "com.unknown.vpn",
            appName: "Super VPN Client"
        )
        XCTAssertTrue(rule.matches(identity: identity))
    }

    func test_networkExtensionRule_doesNotMatch_unrelated() {
        let rule = NetworkExtensionRule()
        let identity = makeIdentity(
            bundleID: "com.apple.Safari",
            appName: "Safari"
        )
        XCTAssertFalse(rule.matches(identity: identity))
    }

    func test_networkExtensionRule_evidence_forSystemExtensions() {
        let rule = NetworkExtensionRule()
        let identity = makeIdentity(bundleID: "at.obdev.littlesnitch", appName: "Little Snitch")
        let url = URL(fileURLWithPath: "/Library/SystemExtensions/at.obdev.LittleSnitchNetworkExtension.systemextension")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .rule })
    }

    func test_networkExtensionRule_evidence_forLaunchDaemon() {
        let rule = NetworkExtensionRule()
        let identity = makeIdentity(bundleID: "at.obdev.littlesnitch", appName: "Little Snitch")
        let url = URL(fileURLWithPath: "/Library/LaunchDaemons/at.obdev.littlesnitch.agent.plist")
        let evidence = rule.evidence(for: url, identity: identity)
        XCTAssertTrue(evidence.contains { $0.source == .bundleID })
    }

    // MARK: - Registry Integration Tests

    func test_registry_returns_adobeRule_for_adobeApp() async {
        let registry = ApplicationRuleRegistry.createDefault()
        let identity = makeIdentity(
            bundleID: "com.adobe.Photoshop",
            appName: "Adobe Photoshop",
            teamID: "JQ5W7278T3"
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Adobe")
    }

    func test_registry_returns_officeRule_for_word() async {
        let registry = ApplicationRuleRegistry.createDefault()
        let identity = makeIdentity(
            bundleID: "com.microsoft.word",
            appName: "Microsoft Word",
            teamID: "UBF8T346G9"
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Microsoft Office")
    }

    func test_registry_returns_steamRule() async {
        let registry = ApplicationRuleRegistry.createDefault()
        let identity = makeIdentity(
            bundleID: "com.valvesoftware.steam",
            appName: "Steam"
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Steam")
    }

    func test_registry_returns_epicRule() async {
        let registry = ApplicationRuleRegistry.createDefault()
        let identity = makeIdentity(
            bundleID: "com.epicgames.EpicGamesLauncher",
            appName: "Epic Games Launcher"
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Epic Games")
    }

    func test_registry_returns_unityRule() async {
        let registry = ApplicationRuleRegistry.createDefault()
        let identity = makeIdentity(
            bundleID: "com.unity3d.unityhub",
            appName: "Unity Hub"
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Unity")
    }

    func test_registry_returns_networkExtensionRule_for_littleSnitch() async {
        let registry = ApplicationRuleRegistry.createDefault()
        let identity = makeIdentity(
            bundleID: "at.obdev.littlesnitch",
            appName: "Little Snitch"
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "Little Snitch")
    }

    func test_registry_returns_networkExtensionRule_for_nordVPN() async {
        let registry = ApplicationRuleRegistry.createDefault()
        let identity = makeIdentity(
            bundleID: "com.nordvpn.macos",
            appName: "NordVPN"
        )
        let rule = await registry.bestRule(for: identity)
        XCTAssertEqual(rule.displayName, "NordVPN")
    }

    // MARK: - Fixture Loading Tests

    func test_loadAllFixtures() throws {
        let fixtureNames = [
            "AdobeCC", "MicrosoftOffice", "Steam", "EpicGames",
            "Unity", "Homebrew", "LittleSnitch", "NordVPN", "Arc",
        ]
        for name in fixtureNames {
            let fixture = try loadFixture(name)
            XCTAssertEqual(fixture.app, name.replacingOccurrences(of: "CC", with: " Creative Cloud")
                .replacingOccurrences(of: "Homebrew", with: "Homebrew")
                .replacingOccurrences(of: "Arc", with: "Arc"))
            XCTAssertFalse(fixture.mustFind.isEmpty, "\(name) mustFind is empty")
            XCTAssertGreaterThanOrEqual(fixture.scoreFloor, 0, "\(name) scoreFloor is negative")
        }
    }

    func test_fixture_adobeCC_hasExpectedPaths() throws {
        let fixture = try loadFixture("AdobeCC")
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("Application Support/Adobe") })
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("Preferences/Adobe") })
    }

    func test_fixture_microsoftOffice_hasGroupContainers() throws {
        let fixture = try loadFixture("MicrosoftOffice")
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("UBF8T346G9.Office") })
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("licensingV2") })
    }

    func test_fixture_steam_hasSteamApps() throws {
        let fixture = try loadFixture("Steam")
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("Application Support/Steam") })
        XCTAssertFalse(fixture.developerArtifacts.isEmpty)
    }

    func test_fixture_epicGames_hasVaultCache() throws {
        let fixture = try loadFixture("EpicGames")
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("Epic") })
        XCTAssertFalse(fixture.developerArtifacts.isEmpty)
    }

    func test_fixture_littleSnitch_hasLaunchDaemons() throws {
        let fixture = try loadFixture("LittleSnitch")
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("LaunchDaemons") })
    }

    func test_fixture_nordVPN_hasLaunchDaemons() throws {
        let fixture = try loadFixture("NordVPN")
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("LaunchDaemons") })
        XCTAssertTrue(fixture.mustFind.contains { $0.contains("PrivilegedHelperTools") })
    }

    // MARK: - Helpers

    private func makeIdentity(
        bundleID: String,
        appName: String,
        teamID: String? = nil
    ) -> AppIdentity {
        AppIdentity(
            bundleID: bundleID,
            appName: appName,
            bundleName: appName,
            bundleVersion: "1.0",
            executableName: appName,
            teamID: teamID,
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
    }

    private func loadFixture(_ name: String) throws -> BaselineFixture {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw TestError.fixtureNotFound(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BaselineFixture.self, from: data)
    }
}
