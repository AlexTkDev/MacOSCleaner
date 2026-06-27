import XCTest
@testable import MacOSCleaner

final class EvidenceExplanationTests: XCTestCase {
    func test_explanation_for_bundleIDExact() {
        let exp = EvidenceExplanations.explanation(for: .bundleIDExact)
        XCTAssertEqual(exp.evidence, .bundleIDExact)
        XCTAssertEqual(exp.category, .identity)
        XCTAssertFalse(exp.title.isEmpty)
        XCTAssertFalse(exp.description.isEmpty)
    }

    func test_explanation_for_teamID_withArg() {
        let exp = EvidenceExplanations.explanation(for: .teamID, args: "ABC123")
        XCTAssertEqual(exp.evidence, .teamID)
        XCTAssertFalse(exp.description.isEmpty)
    }

    func test_explanations_groupedByCategory() {
        let evidence: Set<Evidence> = [.bundleIDExact, .teamID, .launchAgent]
        let grouped = EvidenceExplanations.explanations(for: evidence)
        XCTAssertNotNil(grouped[.identity])
        XCTAssertNotNil(grouped[.signature])
        XCTAssertNotNil(grouped[.system])
    }

    func test_explanations_withContext_bundleIDPrefix() {
        let ctx = ExplanationContext(bundleID: "com.test.app", appName: "TestApp", teamID: nil)
        let evidence: Set<Evidence> = [.bundleIDPrefix]
        let grouped = EvidenceExplanations.explanations(for: evidence, context: ctx)
        let exps = grouped[.identity]
        XCTAssertEqual(exps?.count, 1)
    }

    func test_explanations_withContext_teamID() {
        let ctx = ExplanationContext(bundleID: nil, appName: "App", teamID: "TEAM123")
        let evidence: Set<Evidence> = [.teamID]
        let grouped = EvidenceExplanations.explanations(for: evidence, context: ctx)
        let exps = grouped[.signature]
        XCTAssertEqual(exps?.count, 1)
    }

    func test_explanations_sortedByRawValue() {
        let evidence: Set<Evidence> = [.teamID, .bundleIDExact, .vendorName]
        let grouped = EvidenceExplanations.explanations(for: evidence)
        for (_, exps) in grouped {
            for i in 1..<exps.count {
                XCTAssertTrue(exps[i - 1].evidence.rawValue <= exps[i].evidence.rawValue)
            }
        }
    }

    func test_explanations_emptySet() {
        let grouped = EvidenceExplanations.explanations(for: [])
        XCTAssertTrue(grouped.isEmpty)
    }
}
