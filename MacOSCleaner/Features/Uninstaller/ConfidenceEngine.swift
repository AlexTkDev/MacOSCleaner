import Foundation

public enum ConfidenceEngine {
    public static let criticalEvidence: Set<Evidence> = [
        .bundleIDExact, .bundleIDPrefix, .packageReceipt, .knownCatalog,
        .spotlightBundleAttr, .loginItem,
    ]

    public static func assess(_ evidence: Set<Evidence>, ruleScore: Int = 0, identity: AppIdentity, weights: ScoringWeights = .default) -> ConfidenceAssessment {
        let score = weights.score(evidence) + ruleScore
        let missing = criticalEvidence.subtracting(evidence)

        var tier: ConfidenceTier
        if score >= 100 {
            if evidence.contains(.bundleIDExact) || evidence.contains(.bundleIDPrefix)
                || evidence.contains(.packageReceipt) || evidence.contains(.knownCatalog)
                || evidence.contains(.spotlightBundleAttr) || evidence.contains(.loginItem)
                || ruleScore >= 100
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

        // Mega-vendors (Google/Microsoft/Adobe): vendor-only evidence is shared-suite noise.
        // Product identity (appNamePrefix / executableName) under a vendor hub is enough —
        // e.g. Google/AndroidStudio* must not demote to possible.
        let bid = identity.bundleID.lowercased()
        let isMegaVendorApp = bid.contains("google") || bid.contains("microsoft") || bid.contains("adobe")
        if isMegaVendorApp && evidence.contains(.vendorName)
            && !evidence.contains(.appNameExact) && !evidence.contains(.appNamePrefix)
            && !evidence.contains(.executableName)
            && !evidence.contains(.bundleIDExact) && !evidence.contains(.bundleIDPrefix)
            && !evidence.contains(.knownCatalog)
            && !evidence.contains(.appGroup) && !evidence.contains(.container) {
            let strong = evidence.filter {
                $0 != .vendorName && $0 != .parentDirectory && $0 != .spotlight
            }.count
            if strong < 2 {
                if tier == .guaranteed || tier == .veryLikely { tier = .possible }
                else { tier = .ignore }
            }
        }

        // App-matching diagnostic reports and updaters (e.g. Chrome Helper diag, xcodebuild diag, OpenCode updater)
        let hasAppOrExecEvidence = evidence.contains(.appNameExact) || evidence.contains(.appNamePrefix)
            || evidence.contains(.executableName) || evidence.contains(.bundleIDExact) || evidence.contains(.bundleIDPrefix)
        if hasAppOrExecEvidence && score >= 30 {
            if tier == .possible {
                tier = .veryLikely
            }
        }

        return ConfidenceAssessment(evidence: evidence, score: score, tier: tier, missingCritical: Array(missing))
    }

    public static func assessAll(_ nodes: [EvidenceGraphNode], identity: AppIdentity, weights: ScoringWeights = .default) -> [ConfidenceAssessment] {
        nodes.map { assess($0.evidence, identity: identity, weights: weights) }
    }
}
