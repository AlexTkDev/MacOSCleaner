import Foundation

public struct LeftoverItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let url: URL
    public let appName: String
    public let bundleID: String?
    public let sizeBytes: Int64
    public let score: Int
    public let evidence: [ArtifactEvidence]
    public let rawEvidence: Set<Evidence>
    public let confidence: ConfidenceTier
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        appName: String,
        bundleID: String?,
        sizeBytes: Int64,
        score: Int,
        evidence: [ArtifactEvidence] = [],
        rawEvidence: Set<Evidence> = [],
        confidence: ConfidenceTier = .possible,
        isSelected: Bool = true
    ) {
        self.id = id
        self.url = NormalizedPath.canonicalize(url)
        self.appName = appName
        self.bundleID = bundleID
        self.sizeBytes = sizeBytes
        self.score = score
        self.evidence = evidence
        self.rawEvidence = rawEvidence
        self.confidence = confidence
        self.isSelected = isSelected
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(NormalizedPath.key(url))
    }

    public static func == (lhs: LeftoverItem, rhs: LeftoverItem) -> Bool {
        NormalizedPath.key(lhs.url) == NormalizedPath.key(rhs.url) && lhs.isSelected == rhs.isSelected
    }
}

public struct VerificationReport: Sendable {
    public let appName: String
    public let bundleID: String?
    public let leftovers: [ScoredArtifact]
    public let items: [LeftoverItem]
    public let count: Int

    public var totalSizeBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    public var hasLeftovers: Bool { count > 0 }

    public init(
        appName: String = "",
        bundleID: String? = nil,
        leftovers: [ScoredArtifact] = [],
        items: [LeftoverItem] = []
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.leftovers = leftovers
        if !items.isEmpty {
            self.items = items
            self.count = items.count
        } else {
            self.items = leftovers.map {
                LeftoverItem(
                    url: $0.url,
                    appName: appName,
                    bundleID: bundleID,
                    sizeBytes: FileManager.default.getDirectorySize(url: $0.url),
                    score: $0.score,
                    evidence: $0.evidence,
                    confidence: .possible
                )
            }
            self.count = leftovers.count
        }
    }
}

