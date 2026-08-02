import XCTest
@testable import MacOSCleaner

final class WeightABTests: XCTestCase {
    
    func testWeightABComparison() async throws {
        // Skip if not explicitly requested or in CI
        // XCTSkip("Run this manually for A/B testing weights")
        
        let testApps = [
            "com.google.Chrome",
            "com.tinyspeck.slackmacgap",
            "org.telegram.desktop",
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.docker.docker",
            "org.mozilla.firefox",
            "com.spotify.client",
            "com.hnc.Discord",
            "us.zoom.xos"
        ]
        
        let discovery = AppDiscovery()
        let installedURLs = await discovery.findAll()
        let commandRunner = CommandRunner()
        
        var identities: [AppIdentity] = []
        for url in installedURLs {
            let identity = await AppIdentity.resolve(from: url, commandRunner: commandRunner)
            if testApps.contains(identity.bundleID) {
                identities.append(identity)
            }
        }
        
        guard !identities.isEmpty else {
            throw XCTSkip("None of the test apps are installed.")
        }
        
        let collector = CandidateCollector(
            fileSystemContext: .production,
            commandRunner: commandRunner
        )
        let probe = EvidenceProbe(commandRunner: commandRunner)
        let registry = ApplicationRuleRegistry.shared
        
        var oldWeights = ScoringWeights.default
        oldWeights.appNameExact = 60
        oldWeights.spotlight = 5
        oldWeights.electronCache = 40
        
        let newWeights = ScoringWeights.default // Already updated to 80, 15, 60
        
        print("| App | Current | New | Gained | Lost | Tier↑ | Tier↓ |")
        print("|---|---|---|---|---|---|---|")
        
        for identity in identities {
            let candidates = await collector.collect(identity: identity, mode: .balanced)
            let result = await collector.resolve(identity: identity, candidates: candidates)
            let rule = await registry.bestRule(for: identity)
            
            var currentCount = 0
            var newCount = 0
            var tierUp = 0
            var tierDown = 0
            
            for item in result.candidates {
                let evidence = await probe.probe(url: item, identity: identity)
                let currentScore = oldWeights.score(evidence) + rule.evidence(for: item, identity: identity).reduce(0) { $0 + oldWeights.weight(for: $1) }
                let newScore = newWeights.score(evidence) + rule.evidence(for: item, identity: identity).reduce(0) { $0 + newWeights.weight(for: $1) }
                
                let currentTier = ConfidenceTier(score: currentScore)
                let newTier = ConfidenceTier(score: newScore)
                
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
}
