import Foundation

// MARK: — EvidenceSource (coarser categories for scoring + negative)

public enum EvidenceSource: Hashable, Sendable {
    case rule
    case bundleID
    case teamID
    case appName
    case plistContent
    case spotlight
    case parentFolder
    case developerSignature
    case foreignBundleID
    case foreignTeamID
    case systemArtifact
}

// MARK: — ArtifactEvidence (explainable evidence point)

public struct ArtifactEvidence: Hashable, Sendable {
    public let source: EvidenceSource
    public let weight: Int

    public init(source: EvidenceSource, weight: Int) {
        self.source = source
        self.weight = weight
    }
}

// MARK: — ScoredArtifact (output of scoring pipeline)

public struct ScoredArtifact: Hashable, Sendable {
    public let url: URL
    public let score: Int
    public let evidence: [ArtifactEvidence]

    public init(url: URL, score: Int, evidence: [ArtifactEvidence]) {
        self.url = url
        self.score = score
        self.evidence = evidence
    }
}

// MARK: — ScoreThresholds (configurable, not hardcoded)

public struct ScoreThresholds: Sendable, Equatable {
    public var guaranteed: Int
    public var veryLikely: Int
    public var possible: Int

    public static let `default` = ScoreThresholds(
        guaranteed: 100,
        veryLikely: 60,
        possible: 30
    )

    public init(guaranteed: Int, veryLikely: Int, possible: Int) {
        self.guaranteed = guaranteed
        self.veryLikely = veryLikely
        self.possible = possible
    }
}

// MARK: — Bridge from Evidence → EvidenceSource

extension Evidence {
    public var source: EvidenceSource {
        switch self {
        case .bundleIDExact, .bundleIDPrefix:
            return .bundleID
        case .appNameExact, .appNamePrefix:
            return .appName
        case .teamID:
            return .teamID
        case .developerSignature:
            return .developerSignature
        case .parentDirectory:
            return .parentFolder
        case .plistContent:
            return .plistContent
        case .spotlight, .spotlightBundleAttr, .spotlightCreator:
            return .spotlight
        case .vendorName, .frameworkName, .xpcServiceName, .plugInName,
             .executableName, .fileContent,
             .electronCache, .jetBrainsConfig, .flutterBuild,
             .launchAgent, .launchDaemon, .loginItem,
             .appGroup, .container, .extension, .xpcConnection,
             .packageReceipt, .launchServicesRegistered:
            return .rule
        }
    }
}

// MARK: — Build ArtifactEvidence from a set of Evidence

extension Sequence where Element == Evidence {
    public func artifactEvidence(weights: ScoringWeights = .default) -> [ArtifactEvidence] {
        var seen = Set<EvidenceSource>()
        var result: [ArtifactEvidence] = []
        for e in self {
            let s = e.source
            if !seen.contains(s) {
                let w = weights.weight(for: s)
                result.append(ArtifactEvidence(source: s, weight: w))
                seen.insert(s)
            }
        }
        return result
    }

    public func totalScore(weights: ScoringWeights = .default) -> Int {
        artifactEvidence(weights: weights).reduce(0) { $0 + $1.weight }
    }
}

// MARK: — ScoringWeights adds source-based lookup

extension ScoringWeights {
    public func weight(for source: EvidenceSource) -> Int {
        switch source {
        case .bundleID: return bundleIDExact
        case .teamID: return teamID
        case .appName: return appNameExact
        case .plistContent: return plistContent
        case .spotlight: return self.spotlight
        case .parentFolder: return parentDirectory
        case .developerSignature: return self.developerSignature
        case .rule:
            return 0
        case .foreignBundleID: return -200
        case .foreignTeamID: return -150
        case .systemArtifact: return -100
        }
    }
}
