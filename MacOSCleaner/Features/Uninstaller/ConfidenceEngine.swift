import Foundation

public enum ConfidenceEngine {
    public static let criticalEvidence: Set<Evidence> = [
        .bundleIDExact, .bundleIDPrefix, .packageReceipt,
        .spotlightBundleAttr, .loginItem,
    ]

    public static func assess(_ evidence: Set<Evidence>, identity: AppIdentity, weights: ScoringWeights = .default) -> ConfidenceAssessment {
        let score = weights.score(evidence)
        let missing = criticalEvidence.subtracting(evidence)

        var tier: ConfidenceTier
        if score >= 100 {
            if evidence.contains(.bundleIDExact) || evidence.contains(.bundleIDPrefix)
                || evidence.contains(.packageReceipt) || evidence.contains(.spotlightBundleAttr)
                || evidence.contains(.loginItem)
                || (evidence.contains(.teamID) && (evidence.contains(.launchAgent) || evidence.contains(.launchDaemon)
                    || evidence.contains(.extension) || evidence.contains(.appGroup) || evidence.contains(.container))) {
                tier = .guaranteed
            } else {
                tier = .veryLikely
            }
        } else if score >= 60 {
            tier = .veryLikely
        } else if score >= 30 {
            tier = .possible
        } else {
            tier = .ignore
        }

        if identity.isJetBrains && evidence.contains(.vendorName) && !evidence.contains(.appNameExact) && !evidence.contains(.bundleIDPrefix) {
            let nonVendorCount = evidence.filter { $0 != .vendorName && $0 != .parentDirectory }.count
            if nonVendorCount < 3 {
                if tier == .guaranteed { tier = .veryLikely }
                else if tier == .veryLikely { tier = .possible }
                else { tier = .ignore }
            }
        }

        return ConfidenceAssessment(evidence: evidence, score: score, tier: tier, missingCritical: Array(missing))
    }

    public static func assessAll(_ nodes: [EvidenceGraphNode], identity: AppIdentity, weights: ScoringWeights = .default) -> [ConfidenceAssessment] {
        nodes.map { assess($0.evidence, identity: identity, weights: weights) }
    }
}
