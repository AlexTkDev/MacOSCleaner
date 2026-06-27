import XCTest
@testable import MacOSCleaner

final class ArtifactClassifierTests: XCTestCase {
    private func makeArtifact(path: String, score: Int, evidence: [ArtifactEvidence] = []) -> ScoredArtifact {
        ScoredArtifact(url: URL(fileURLWithPath: path), score: score, evidence: evidence)
    }

    func test_high_score_is_related() {
        let a = makeArtifact(path: "/Users/test/Library/Application Support/Postman", score: 190)
        XCTAssertEqual(ArtifactClassifier.classify(a), .related)
    }

    func test_veryLikely_score_is_related() {
        let a = makeArtifact(path: "/Users/test/Library/Caches/com.postmanlabs.mac", score: 80)
        XCTAssertEqual(ArtifactClassifier.classify(a), .related)
    }

    func test_possible_score_is_related() {
        let a = makeArtifact(path: "/Users/test/Library/Preferences/com.postmanlabs.mac.plist", score: 45)
        XCTAssertEqual(ArtifactClassifier.classify(a), .related)
    }

    func test_low_score_is_ignored() {
        let a = makeArtifact(path: "/Users/test/Library/Caches/random.tmp", score: 10)
        XCTAssertEqual(ArtifactClassifier.classify(a), .ignored)
    }

    func test_negative_evidence_is_ignored() {
        let e = [ArtifactEvidence(source: .foreignBundleID, weight: -200)]
        let a = makeArtifact(path: "/Users/test/Library/Preferences/com.adguard.mac.vpn.plist", score: -200, evidence: e)
        XCTAssertEqual(ArtifactClassifier.classify(a), .ignored)
    }

    func test_developer_path_is_developer() {
        let a = makeArtifact(path: "/Users/test/Library/Developer/Xcode/DerivedData", score: 150)
        XCTAssertEqual(ArtifactClassifier.classify(a), .developer)
    }

    func test_gradle_is_developer() {
        let a = makeArtifact(path: "/Users/test/.gradle", score: 120)
        XCTAssertEqual(ArtifactClassifier.classify(a), .developer)
    }

    func test_classifyBatch_splits_correctly() {
        let related = makeArtifact(path: "/Library/Application Support/Postman", score: 190)
        let developer = makeArtifact(path: "/Users/test/.gradle", score: 120)
        let ignored = makeArtifact(path: "/tmp/random", score: 5)

        let (r, d, i) = ArtifactClassifier.classifyBatch([related, developer, ignored])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(i.count, 1)
    }

    func test_systemArtifact_is_ignored_regardless_of_score() {
        let e = [ArtifactEvidence(source: .systemArtifact, weight: -100)]
        let a = makeArtifact(path: "/System/Library/Something", score: 200, evidence: e)
        XCTAssertEqual(ArtifactClassifier.classify(a), .ignored)
    }

    func test_custom_thresholds() {
        let strict = ScoreThresholds(guaranteed: 200, veryLikely: 150, possible: 130)
        let a = makeArtifact(path: "/Users/test/Library/Caches/App", score: 120)
        XCTAssertEqual(ArtifactClassifier.classify(a, thresholds: strict), .ignored)
    }
}
