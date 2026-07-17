import XCTest
@testable import MacOSCleaner

final class CandidateCollectorTests: XCTestCase {
    func test_collect_findsAppSupportDirByExactName() async throws {
        let appName = "CollectorTestApp_\(UUID().uuidString.prefix(8))"
        let fixture = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/\(appName)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let collector = CandidateCollector()
        let identity = AppIdentity(
            bundleID: "com.test.\(appName)",
            appName: String(appName),
            bundleName: nil,
            bundleVersion: nil,
            executableName: String(appName),
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(appName).app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["TestVendor"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertTrue(candidates.contains { $0.path == fixture.path }, "Collector must find Application Support dir by exact name")
    }

    func test_collect_safeMode_findsExactMatches() async throws {
        let appName = "CollectorSafeApp_\(UUID().uuidString.prefix(8))"
        let bundleID = "com.test.\(appName)"
        let fixture = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/\(bundleID)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let collector = CandidateCollector()
        let identity = AppIdentity(
            bundleID: bundleID,
            appName: String(appName),
            bundleName: nil,
            bundleVersion: nil,
            executableName: String(appName),
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(appName).app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity, mode: .safe)
        XCTAssertTrue(candidates.contains { $0.path == fixture.path }, "Safe mode must find cache dir by exact bundle ID")
    }

    func test_collect_findsNestedCacheByTokenPrefix() async throws {
        let appName = "OpenCode"
        let home = NSHomeDirectory()
        let nested = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Caches/com.other.updater/UpdaterCache/opencode-desktop_br")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/com.other.updater")) }

        let collector = CandidateCollector()
        let identity = AppIdentity(
            bundleID: "dev.opencode.desktop",
            appName: appName,
            bundleName: nil,
            bundleVersion: nil,
            executableName: appName,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/OpenCode.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["opencode"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertTrue(candidates.contains { $0.path == nested.path })
    }

    func test_collect_skipsGenericBundleTailOutsideVendorContext() async throws {
        let marker = "TailFP\(UUID().uuidString.prefix(8))"
        let home = NSHomeDirectory()
        let root = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/\(marker)")
        // ai.<x>.desktop must not claim a folder named "desktop" outside vendor context
        let trap = root.appendingPathComponent("Data/desktop")
        try FileManager.default.createDirectory(at: trap, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let collector = CandidateCollector()
        let identity = AppIdentity(
            bundleID: "ai.\(marker.lowercased()).desktop",
            appName: "\(marker)App",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "\(marker)App",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(marker)App.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [marker.lowercased()],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertFalse(candidates.contains { $0.path == trap.path },
                       "Generic bundle-ID tail must not match folders outside a vendor dir")
    }

    func test_collect_findsGroupContainerFromEntitlements() async throws {
        let marker = "grp\(UUID().uuidString.prefix(8).lowercased())"
        let groupName = "FAKETEAM99.com.\(marker).shared"
        let home = NSHomeDirectory()
        let fixture = URL(fileURLWithPath: home).appendingPathComponent("Library/Group Containers/\(groupName)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let collector = CandidateCollector()
        // No teamID, no name relation — only the entitlements declare the group
        var identity = AppIdentity(
            bundleID: "com.other.\(marker)vpn",
            appName: "Grp\(marker)",
            bundleName: nil,
            bundleVersion: nil,
            executableName: "Grp\(marker)",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Grp\(marker).app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: [],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        identity.appGroups = [groupName]
        let candidates = await collector.collect(identity: identity)
        XCTAssertTrue(candidates.contains { $0.path == fixture.path },
                      "Group container declared in entitlements must be collected")
    }

    func test_collect_findsGoogleChromeVendorPath() async throws {
        let home = NSHomeDirectory()
        let chromeDir = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Google/Chrome")
        try FileManager.default.createDirectory(at: chromeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Google")) }

        let collector = CandidateCollector()
        let identity = AppIdentity(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            bundleName: "Chrome",
            bundleVersion: nil,
            executableName: "Google Chrome",
            teamID: "EQHXZ8M8AV",
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isAppStore: false, isSandboxed: false, isAdHocSigned: false,
            vendorNames: ["Google", "Chrome"],
            helperNames: [], frameworkNames: [], xpcServiceNames: [], plugInNames: [],
            isElectron: false, isJetBrains: false, isFlutter: false,
            isJava: false, isQt: false, isDocker: false
        )
        let candidates = await collector.collect(identity: identity)
        XCTAssertTrue(candidates.contains { $0.path == chromeDir.path })
    }
}
