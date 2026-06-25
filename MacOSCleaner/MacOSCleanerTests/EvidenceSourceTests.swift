import XCTest
@testable import MacOSCleaner

final class EvidenceSourceTests: XCTestCase {
    func test_evidence_maps_to_source() {
        XCTAssertEqual(Evidence.bundleIDExact.source, .bundleID)
        XCTAssertEqual(Evidence.bundleIDPrefix.source, .bundleID)
        XCTAssertEqual(Evidence.appNameExact.source, .appName)
        XCTAssertEqual(Evidence.appNamePrefix.source, .appName)
        XCTAssertEqual(Evidence.teamID.source, .teamID)
        XCTAssertEqual(Evidence.parentDirectory.source, .parentFolder)
        XCTAssertEqual(Evidence.plistContent.source, .plistContent)
        XCTAssertEqual(Evidence.spotlight.source, .spotlight)
        XCTAssertEqual(Evidence.vendorName.source, .rule)
        XCTAssertEqual(Evidence.launchAgent.source, .rule)
        XCTAssertEqual(Evidence.container.source, .rule)
    }

    func test_bundleID_evidence_weight() {
        let set: Set<Evidence> = [.bundleIDExact]
        let evidence = set.artifactEvidence()
        let bundleID = evidence.first { $0.source == .bundleID }
        XCTAssertEqual(bundleID?.weight, 100)
    }

    func test_teamID_evidence_weight() {
        let set: Set<Evidence> = [.teamID]
        let evidence = set.artifactEvidence()
        let teamID = evidence.first { $0.source == .teamID }
        XCTAssertEqual(teamID?.weight, 50)
    }

    func test_negative_evidence_weight() {
        let weights = ScoringWeights.default
        XCTAssertEqual(weights.weight(for: .foreignBundleID), -200)
        XCTAssertEqual(weights.weight(for: .foreignTeamID), -150)
        XCTAssertEqual(weights.weight(for: .systemArtifact), -100)
    }

    func test_artifactEvidence_deduplicates_sources() {
        let set: Set<Evidence> = [.bundleIDExact, .bundleIDPrefix]
        let evidence = set.artifactEvidence()
        let bundleIDCount = evidence.filter { $0.source == .bundleID }.count
        XCTAssertEqual(bundleIDCount, 1)
    }

    func test_scoredArtifact_total_score() {
        let evidence: [ArtifactEvidence] = [
            ArtifactEvidence(source: .bundleID, weight: 100),
            ArtifactEvidence(source: .teamID, weight: 50),
        ]
        let artifact = ScoredArtifact(url: URL(fileURLWithPath: "/test"), score: 150, evidence: evidence)
        XCTAssertEqual(artifact.score, 150)
    }

    func test_scoreThresholds_defaults() {
        let t = ScoreThresholds.default
        XCTAssertEqual(t.guaranteed, 100)
        XCTAssertEqual(t.veryLikely, 60)
        XCTAssertEqual(t.possible, 30)
    }
}
