import XCTest
@testable import MacOSCleaner

final class HelperAppCollapserTests: XCTestCase {
    func test_collapse_chromeHelperIntoChrome() {
        let chrome = makeApp(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            path: "/Applications/Google Chrome.app"
        )
        let helper = makeApp(
            name: "Google Chrome Helper",
            bundleID: "com.google.Chrome.helper",
            path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app"
        )
        let result = HelperAppCollapser.collapse([chrome, helper])
        XCTAssertEqual(result.apps.count, 1)
        XCTAssertEqual(result.apps[0].bundleID, "com.google.Chrome")
        // Nested helper .app is covered by parent delete — not listed as absorbed URL.
        XCTAssertFalse(result.apps[0].absorbedHelperURLs.contains(where: {
            $0.path == helper.url.path
        }))
    }

    func test_collapse_todesktopHelperByBundlePrefix() {
        let cursor = makeApp(
            name: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            path: "/Applications/Cursor.app",
            isElectron: true
        )
        let helper = makeApp(
            name: "Cursor Helper",
            bundleID: "com.todesktop.230313mzl4w4u92.helper",
            path: "/private/var/folders/xx/C/com.todesktop.230313mzl4w4u92.helper"
        )
        let result = HelperAppCollapser.collapse([cursor, helper])
        XCTAssertEqual(result.apps.count, 1)
        XCTAssertTrue(result.apps[0].absorbedHelperURLs.contains(where: {
            $0.path == helper.url.path
        }))
    }

    func test_collapse_electronPluginHelperByNamePrefix() {
        let cursor = makeApp(
            name: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            path: "/Applications/Cursor.app",
            isElectron: true
        )
        let plugin = makeApp(
            name: "Cursor Helper (Plugin)",
            bundleID: "com.github.Electron.helper",
            path: "/private/var/folders/xx/C/com.github.Electron.helper"
        )
        let result = HelperAppCollapser.collapse([cursor, plugin])
        XCTAssertEqual(result.apps.count, 1)
        XCTAssertEqual(result.apps[0].name, "Cursor")
        XCTAssertTrue(result.apps[0].absorbedHelperURLs.contains(where: { $0.path == plugin.url.path }))
    }

    func test_enclosingAppBundlePath() {
        XCTAssertEqual(
            HelperAppCollapser.enclosingAppBundlePath(
                "/Applications/Cursor.app/Contents/Frameworks/Helper.app/Contents"
            ),
            "/Applications/Cursor.app"
        )
        XCTAssertNil(HelperAppCollapser.enclosingAppBundlePath("/private/var/folders/x/C/foo.helper"))
    }

    func test_isLikelyHelperURL() {
        XCTAssertTrue(HelperAppCollapser.isLikelyHelperURL(
            URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app")
        ))
        XCTAssertFalse(HelperAppCollapser.isLikelyHelperURL(
            URL(fileURLWithPath: "/Applications/Google Chrome.app")
        ))
    }

    private func makeApp(
        name: String,
        bundleID: String,
        path: String,
        isElectron: Bool = false
    ) -> UninstallerService.AppInfo {
        let url = URL(fileURLWithPath: path)
        let identity = AppIdentity(
            bundleID: bundleID,
            appName: name,
            bundleName: name,
            bundleVersion: "1",
            executableName: name,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: url,
            isAppStore: false,
            isSandboxed: false,
            isAdHocSigned: false,
            vendorNames: [],
            helperNames: [],
            frameworkNames: isElectron ? ["Electron"] : [],
            xpcServiceNames: [],
            plugInNames: [],
            appGroups: [],
            isElectron: isElectron,
            isJetBrains: false,
            isFlutter: false,
            isJava: false,
            isQt: false,
            isDocker: false
        )
        return UninstallerService.AppInfo(
            url: url,
            bundleID: bundleID,
            name: name,
            relatedFiles: [],
            developerComponents: [],
            absorbedHelperURLs: [],
            identity: identity,
            scanState: .discovered,
            size: 100,
            version: "1",
            lastUsed: nil,
            iconData: nil
        )
    }
}
