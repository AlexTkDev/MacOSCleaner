import XCTest
@testable import MacOSCleaner

final class WeightABTests: XCTestCase {

    func testWeightABComparison() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let commandRunner = CommandRunner()
        let appDir = ctx.homeDirectory.appendingPathComponent("Applications/Example.app/Contents")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.example.isolated</string>
        <key>CFBundleName</key><string>Example</string>
        <key>CFBundleExecutable</key><string>Example</string>
        </dict></plist>
        """
        try plist.write(to: appDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let identity = await AppIdentity.resolve(
            from: appDir.deletingLastPathComponent(),
            commandRunner: commandRunner
        )
        let identities = [identity]

        let collector = CandidateCollector(
            commandRunner: commandRunner,
            fileSystemContext: ctx
        )
        let probe = EvidenceProbe(commandRunner: commandRunner)
        let registry = ApplicationRuleRegistry.shared
        let thresholds = ScoreThresholds.default

        var oldWeights = ScoringWeights.default
        oldWeights.appNameExact = 60
        oldWeights.spotlight = 5
        oldWeights.electronCache = 40

        let newWeights = ScoringWeights.default // Already updated to 80, 15, 60

        print("| App | Current | New | Gained | Lost | Tier↑ | Tier↓ |")
        print("|---|---|---|---|---|---|---|")

        for identity in identities {
            let candidates = await collector.collect(identity: identity, mode: .balanced)
            let rule = await registry.bestRule(for: identity)

            var currentCount = 0
            var newCount = 0
            var tierUp = 0
            var tierDown = 0

            for item in candidates {
                let evidence = await probe.probe(url: item, identity: identity)
                // rule.evidence returns [ArtifactEvidence] with pre-computed weights
                let ruleScore = rule.evidence(for: item, identity: identity).reduce(0) { $0 + $1.weight }
                let currentScore = oldWeights.score(evidence) + ruleScore
                let newScore = newWeights.score(evidence) + ruleScore

                let currentTier = tier(for: currentScore, thresholds: thresholds)
                let newTier = tier(for: newScore, thresholds: thresholds)

                let currentIncluded = currentTier >= .veryLikely
                let newIncluded = newTier >= .veryLikely

                if currentIncluded { currentCount += 1 }
                if newIncluded { newCount += 1 }

                if currentIncluded && !newIncluded {
                    tierDown += 1
                } else if !currentIncluded && newIncluded {
                    tierUp += 1
                } else if currentTier.rawValue < newTier.rawValue {
                    tierUp += 1
                } else if currentTier.rawValue > newTier.rawValue {
                    tierDown += 1
                }
            }

            let gained = max(0, newCount - currentCount)
            let lost = max(0, currentCount - newCount)

            print("| \(identity.appName) | \(currentCount) | \(newCount) | +\(gained) | -\(lost) | \(tierUp) | \(tierDown) |")
        }
    }

    // MARK: - Helpers

    private func tier(for score: Int, thresholds: ScoreThresholds) -> ConfidenceTier {
        if score >= thresholds.guaranteed { return .guaranteed }
        if score >= thresholds.veryLikely { return .veryLikely }
        if score >= thresholds.possible { return .possible }
        return .ignore
    }
}
