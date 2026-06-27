import XCTest
@testable import MacOSCleaner

final class EvidenceCategoryTests: XCTestCase {
    func test_identity_category() {
        XCTAssertEqual(Evidence.bundleIDExact.category, .identity)
        XCTAssertEqual(Evidence.bundleIDPrefix.category, .identity)
        XCTAssertEqual(Evidence.appNameExact.category, .identity)
        XCTAssertEqual(Evidence.appNamePrefix.category, .identity)
        XCTAssertEqual(Evidence.executableName.category, .identity)
        XCTAssertEqual(Evidence.frameworkName.category, .identity)
        XCTAssertEqual(Evidence.xpcServiceName.category, .identity)
        XCTAssertEqual(Evidence.plugInName.category, .identity)
        XCTAssertEqual(Evidence.vendorName.category, .identity)
    }

    func test_signature_category() {
        XCTAssertEqual(Evidence.teamID.category, .signature)
        XCTAssertEqual(Evidence.developerSignature.category, .signature)
    }

    func test_system_category() {
        XCTAssertEqual(Evidence.launchAgent.category, .system)
        XCTAssertEqual(Evidence.launchDaemon.category, .system)
        XCTAssertEqual(Evidence.loginItem.category, .system)
        XCTAssertEqual(Evidence.appGroup.category, .system)
        XCTAssertEqual(Evidence.container.category, .system)
        XCTAssertEqual(Evidence.extension.category, .system)
        XCTAssertEqual(Evidence.xpcConnection.category, .system)
    }

    func test_metadata_category() {
        XCTAssertEqual(Evidence.packageReceipt.category, .metadata)
        XCTAssertEqual(Evidence.plistContent.category, .metadata)
    }

    func test_content_category() {
        XCTAssertEqual(Evidence.spotlight.category, .content)
        XCTAssertEqual(Evidence.spotlightBundleAttr.category, .content)
        XCTAssertEqual(Evidence.spotlightCreator.category, .content)
        XCTAssertEqual(Evidence.fileContent.category, .content)
        XCTAssertEqual(Evidence.electronCache.category, .content)
        XCTAssertEqual(Evidence.jetBrainsConfig.category, .content)
        XCTAssertEqual(Evidence.flutterBuild.category, .content)
    }

    func test_graph_category() {
        XCTAssertEqual(Evidence.parentDirectory.category, .graph)
    }

    func test_launchServices_category() {
        XCTAssertEqual(Evidence.launchServicesRegistered.category, .launchServices)
    }

    func test_allEvidenceCases_haveCategory() {
        for evidence in Evidence.allCases {
            let cat = evidence.category
            XCTAssertNotEqual(cat.rawValue, "")
        }
    }
}
