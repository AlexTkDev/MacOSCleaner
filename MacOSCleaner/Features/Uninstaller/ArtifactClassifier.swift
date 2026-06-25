import Foundation

// MARK: — ArtifactCategory

public enum ArtifactCategory: Hashable, Sendable {
    case related
    case developer
    case ignored
}

// MARK: — ClassifiedArtifact

public struct ClassifiedArtifact: Hashable, Sendable {
    public let artifact: ScoredArtifact
    public let category: ArtifactCategory

    public init(artifact: ScoredArtifact, category: ArtifactCategory) {
        self.artifact = artifact
        self.category = category
    }
}

// MARK: — ArtifactClassifier

public enum ArtifactClassifier {
    public static let developerMarkers: Set<String> = [
        "DerivedData", "CoreSimulator", "Archives",
        "Android/sdk", ".gradle", ".android",
        ".pub-cache", ".dart_tool",
        "Docker.raw", "Docker.qcow2",
        "steamapps/compatdata", "steamapps/shadercache",
        "VaultCache", "PackageCache",
    ]

    public static func classify(
        _ artifact: ScoredArtifact,
        thresholds: ScoreThresholds = .default
    ) -> ArtifactCategory {
        if hasNegativeEvidence(artifact) {
            return .ignored
        }

        if artifact.score >= thresholds.guaranteed {
            if isDeveloperArtifact(artifact) {
                return .developer
            }
            return .related
        }

        if artifact.score >= thresholds.veryLikely {
            if isDeveloperArtifact(artifact) {
                return .developer
            }
            return .related
        }

        if artifact.score >= thresholds.possible {
            if isDeveloperArtifact(artifact) {
                return .developer
            }
            return .related
        }

        return .ignored
    }

    private static func hasNegativeEvidence(_ artifact: ScoredArtifact) -> Bool {
        artifact.evidence.contains { e in
            e.source == .foreignBundleID || e.source == .foreignTeamID || e.source == .systemArtifact
        }
    }

    public static func classifyBatch(
        _ artifacts: [ScoredArtifact],
        thresholds: ScoreThresholds = .default
    ) -> (related: [ClassifiedArtifact], developer: [ClassifiedArtifact], ignored: [ClassifiedArtifact]) {
        var related: [ClassifiedArtifact] = []
        var developer: [ClassifiedArtifact] = []
        var ignored: [ClassifiedArtifact] = []

        for a in artifacts {
            let c = ClassifiedArtifact(artifact: a, category: classify(a, thresholds: thresholds))
            switch c.category {
            case .related: related.append(c)
            case .developer: developer.append(c)
            case .ignored: ignored.append(c)
            }
        }

        return (related, developer, ignored)
    }

    private static func isDeveloperArtifact(_ artifact: ScoredArtifact) -> Bool {
        let path = artifact.url.path.lowercased()
        return developerMarkers.contains(where: { path.contains($0.lowercased()) })
    }
}
