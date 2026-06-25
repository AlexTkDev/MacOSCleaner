import XCTest
@testable import MacOSCleaner

final class UninstallerServiceTests: XCTestCase {
    var service: UninstallerService!

    override func setUp() async throws {
        service = UninstallerService()
    }

    func testScanState_initiallyDiscovered() {
        let app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp"
        )
        XCTAssertEqual(app.scanState, .discovered)
    }

    func testAppInfo_totalSize_withRelatedFiles() {
        var app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp",
            size: 100
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Caches/test.cache"), size: 50),
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Preferences/test.plist"), size: 30),
        ]
        XCTAssertEqual(app.totalSize, 180)
    }

    func testAppInfo_totalSize_ignoresDeselected() {
        var app = UninstallerService.AppInfo(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.test.app",
            name: "TestApp",
            size: 100
        )
        app.relatedFiles = [
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Caches/test.cache"), isSelected: false, size: 50),
            UninstallerService.RelatedFile(url: URL(fileURLWithPath: "/Library/Preferences/test.plist"), size: 30),
        ]
        XCTAssertEqual(app.totalSize, 130)
    }

    func testConfidenceTier_comparable() {
        XCTAssertTrue(ConfidenceTier.possible < ConfidenceTier.veryLikely)
        XCTAssertTrue(ConfidenceTier.veryLikely < ConfidenceTier.guaranteed)
        XCTAssertTrue(ConfidenceTier.ignore < ConfidenceTier.possible)
    }

    func testRelatedFile_evidenceAndConfidence() {
        let file = UninstallerService.RelatedFile(
            url: URL(fileURLWithPath: "/Library/Caches/test.cache"),
            evidence: [.bundleIDExact, .teamID],
            confidence: .guaranteed
        )
        XCTAssertTrue(file.evidence.contains(.bundleIDExact))
        XCTAssertEqual(file.confidence, .guaranteed)
    }

    func testEvidence_category_mapping() {
        XCTAssertEqual(Evidence.bundleIDExact.category, .identity)
        XCTAssertEqual(Evidence.teamID.category, .signature)
        XCTAssertEqual(Evidence.launchAgent.category, .system)
        XCTAssertEqual(Evidence.packageReceipt.category, .metadata)
        XCTAssertEqual(Evidence.spotlight.category, .content)
        XCTAssertEqual(Evidence.parentDirectory.category, .graph)
        XCTAssertEqual(Evidence.launchServicesRegistered.category, .launchServices)
    }
}
