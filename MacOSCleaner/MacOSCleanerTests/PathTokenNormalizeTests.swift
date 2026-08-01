import XCTest
@testable import MacOSCleaner

final class PathTokenNormalizeTests: XCTestCase {
    func test_resolveTemplate_collapsesDoubleSlashFromHome() {
        let home = "/Users/alex"
        let resolved = PathToken.home.resolveTemplate("/<HOME>/Library/Containers/foo", home: home)
        XCTAssertEqual(resolved, "/Users/alex/Library/Containers/foo")
        XCTAssertFalse(resolved.contains("//"))
    }

    func test_resolveTemplate_leadingSlashBeforeAbsoluteTokens() {
        let home = "/Users/alex"
        let cases: [(PathToken, String, String)] = [
            (.containers, "/<CONTAINERS>/ru.keepcoder.Telegram",
             "/Users/alex/Library/Containers/ru.keepcoder.Telegram"),
            (.groupContainers, "/<GROUP_CONTAINERS>/6N38VWS5BX.ru.keepcoder.Telegram",
             "/Users/alex/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"),
            (.appSupport, "/<APP_SUPPORT>/Telegram",
             "/Users/alex/Library/Application Support/Telegram"),
            (.userLib, "/<USER_LIB>/Preferences/foo.plist",
             "/Users/alex/Library/Preferences/foo.plist"),
            (.home, "/<HOME>/.gradle",
             "/Users/alex/.gradle"),
        ]
        for (token, template, expected) in cases {
            let resolved = token.resolveTemplate(template, home: home)
            XCTAssertEqual(resolved, expected, template)
            XCTAssertFalse(resolved.contains("//"), template)
        }
    }

    func test_joinHome_trimsTrailingSlashOnHome() {
        XCTAssertEqual(
            NormalizedPath.joinHome("/Users/alex/", "Library/Containers/foo"),
            "/Users/alex/Library/Containers/foo"
        )
        XCTAssertFalse(NormalizedPath.joinHome("/Users/alex/", "/Library/Caches").contains("//"))
    }

    func test_fileURL_collapsesDoubleSlash() {
        let url = NormalizedPath.url("//Users/alex/Library/Containers/ru.keepcoder.Telegram")
        XCTAssertFalse(url.path.contains("//"))
        XCTAssertEqual(url.path, "/Users/alex/Library/Containers/ru.keepcoder.Telegram")
    }

    func test_collapseDuplicateSlashes() {
        XCTAssertEqual(
            NormalizedPath.string("//Users/alex/.gradle"),
            "/Users/alex/.gradle"
        )
        XCTAssertEqual(
            NormalizedPath.string("/Users/alex//Library//Caches"),
            "/Users/alex/Library/Caches"
        )
        XCTAssertEqual(
            NormalizedPath.string("/Users/alex/Library"),
            "/Users/alex/Library"
        )
    }

    func test_cleanupPathExpander_collapsesDoubleSlashNonGlob() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExpanderSlash-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Containers/foo", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let weird = "//" + String(target.path.drop(while: { $0 == "/" }))
        let expanded = CleanupPathExpander.expand(weird, home: root.path)
        XCTAssertEqual(expanded.count, 1)
        XCTAssertFalse(expanded[0].contains("//"))
    }

    func test_relatedFile_initNormalizesDoubleSlash() {
        let file = UninstallerService.RelatedFile(
            url: URL(fileURLWithPath: "//Users/alex/Library/Containers/ru.keepcoder.Telegram"),
            isSelected: true,
            size: 1,
            deletionRisk: .normal,
            confidence: .guaranteed
        )
        XCTAssertFalse(file.url.path.contains("//"))
        XCTAssertTrue(file.url.path.hasPrefix("/Users/alex/Library/Containers/"))
    }

    func test_relatedCleanupComponent_initNormalizesDoubleSlash() {
        let component = UninstallerService.RelatedCleanupComponent(
            title: "SDK",
            category: .androidSDK,
            sizeBytes: 10,
            url: URL(fileURLWithPath: "//Users/alex/Library/Android"),
            isSelected: false
        )
        XCTAssertFalse(component.url.path.contains("//"))
    }

    func test_urls_collapsesDirectoryAndFileURLForms() {
        let fileForm = NormalizedPath.url("/Users/alex/Library/Caches/com.example.app", isDirectory: false)
        let dirForm = NormalizedPath.url("/Users/alex/Library/Caches/com.example.app", isDirectory: true)
        XCTAssertNotEqual(fileForm.absoluteString, dirForm.absoluteString)
        XCTAssertEqual(NormalizedPath.key(fileForm), NormalizedPath.key(dirForm))

        let collapsed = NormalizedPath.urls([fileForm, dirForm])
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertFalse(collapsed.first!.path.contains("//"))
        XCTAssertEqual(NormalizedPath.key(collapsed.first!), "/Users/alex/Library/Caches/com.example.app")
    }

    func test_canonicalize_dropsDirectoryHint() {
        let dirForm = URL(fileURLWithPath: "/Users/alex/Library/Application Support/Cursor", isDirectory: true)
        let canonical = NormalizedPath.canonicalize(dirForm)
        XCTAssertEqual(NormalizedPath.key(canonical), "/Users/alex/Library/Application Support/Cursor")
        XCTAssertEqual(NormalizedPath.url(dirForm), canonical)
    }

    func test_evidenceGraph_mergesSlashVariantsIntoOneNode() async {
        let identity = AppIdentity(
            bundleID: "com.example.app",
            appName: "Example",
            bundleName: "Example",
            bundleVersion: "1",
            executableName: "Example",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: NormalizedPath.url("/Applications/Example.app"),
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
        let graph = EvidenceGraph(identity: identity)
        let fileForm = NormalizedPath.url("/Users/alex/Library/Caches/com.example.app", isDirectory: false)
        let dirForm = NormalizedPath.url("/Users/alex/Library/Caches/com.example.app", isDirectory: true)

        await graph.record([.bundleIDExact], for: fileForm)
        await graph.record([.knownCatalog], for: dirForm)

        let nodes = await graph.allNodes().filter {
            NormalizedPath.key($0.url) == "/Users/alex/Library/Caches/com.example.app"
        }
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].evidence.contains(.bundleIDExact))
        XCTAssertTrue(nodes[0].evidence.contains(.knownCatalog))

        let assessment = ConfidenceEngine.assess(nodes[0].evidence, ruleScore: 0, identity: identity)
        XCTAssertEqual(assessment.tier, .guaranteed)
    }

    func test_catalogPathMembership_matchesScanDirectoryURL() {
        let catalog = NormalizedPath.url("/Users/alex/Library/Application Support/Google/Chrome")
        let scan = NormalizedPath.url("/Users/alex/Library/Application Support/Google/Chrome", isDirectory: true)
        let catalogKeys = Set([catalog].map(NormalizedPath.key))
        XCTAssertTrue(catalogKeys.contains(NormalizedPath.key(scan)))
        XCTAssertEqual(NormalizedPath.urls([catalog, scan]).count, 1)
    }

    func test_parentLinker_collapsesDoubleSlashFromPathComponents() {
        let identity = AppIdentity(
            bundleID: "ru.keepcoder.Telegram",
            appName: "Telegram",
            bundleName: "Telegram",
            bundleVersion: "1",
            executableName: "Telegram",
            teamID: nil,
            signingAuthority: nil,
            bundleURL: NormalizedPath.url("/Applications/Telegram.app"),
            isAppStore: false,
            isSandboxed: false,
            isAdHocSigned: false,
            vendorNames: ["Telegram"],
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
        // pathComponents join yields leading "//" for absolute paths — helper must collapse.
        let child = NormalizedPath.url("/Users/alex/Library/Containers/ru.keepcoder.Telegram")
        let links = ParentLinker.link(url: child, identity: identity)
        XCTAssertFalse(links.isEmpty)
        for (parent, _) in links {
            XCTAssertFalse(parent.path.contains("//"), parent.path)
        }
    }
}
