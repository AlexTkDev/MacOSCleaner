import Foundation
import OSLog

private extension Logger {
    static let verification = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "VerificationEngine")
}

public actor VerificationEngine {
    private let commandRunner: any CommandRunning
    private let codesignCache: CodesignCache
    private let plistCache: PlistContentCache
    private let thresholds: ScoreThresholds
    private let weights: ScoringWeights
    private let ruleRegistry: ApplicationRuleRegistry
    private let fileSystemContext: FileSystemContext

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        codesignCache: CodesignCache = CodesignCache(),
        plistCache: PlistContentCache = PlistContentCache(),
        thresholds: ScoreThresholds = .default,
        weights: ScoringWeights = .default,
        ruleRegistry: ApplicationRuleRegistry = ApplicationRuleRegistry.createDefault(),
        fileSystemContext: FileSystemContext = .production
    ) {
        self.commandRunner = commandRunner
        self.codesignCache = codesignCache
        self.plistCache = plistCache
        self.thresholds = thresholds
        self.weights = weights
        self.ruleRegistry = ruleRegistry
        self.fileSystemContext = fileSystemContext
    }

    public func verify(identity: AppIdentity) async -> VerificationReport {
        Logger.verification.info("Verifying '\(identity.appName, privacy: .public)' after uninstall")

        let collector = CandidateCollector(
            fileManager: .default,
            commandRunner: commandRunner,
            fileSystemContext: fileSystemContext
        )
        let candidates = await collector.collect(identity: identity)

        guard !candidates.isEmpty else {
            Logger.verification.info("0 leftovers found")
            return VerificationReport(leftovers: [])
        }

        let probe = EvidenceProbe(
            commandRunner: commandRunner,
            codesignCache: codesignCache,
            plistCache: plistCache
        )

        var artifacts: [ScoredArtifact] = []
        var artifactMap: [URL: (evidence: [ArtifactEvidence], rawEvidence: Set<Evidence>, tier: ConfidenceTier, size: Int64)] = [:]
        let rule = await ruleRegistry.bestRule(for: identity)

        for url in candidates {
            let evidence = await probe.probe(url: url, identity: identity)
            let ruleEvidence = rule.evidence(for: url, identity: identity)
            guard !evidence.isEmpty || !ruleEvidence.isEmpty else { continue }

            let artifactEvidence = evidence.artifactEvidence(weights: weights) + ruleEvidence
            let score = artifactEvidence.reduce(0) { $0 + $1.weight }
            let ruleScore = ruleEvidence.reduce(0) { $0 + $1.weight }
            let assessment = ConfidenceEngine.assess(evidence, ruleScore: ruleScore, identity: identity, weights: weights)

            let scored = ScoredArtifact(url: url, score: score, evidence: artifactEvidence)
            artifacts.append(scored)
            let size = FileManager.default.getDirectorySize(url: url)
            artifactMap[url] = (artifactEvidence, evidence, assessment.tier, size)
        }

        let classified = ArtifactClassifier.classifyBatch(artifacts, thresholds: thresholds)

        var leftovers: [ScoredArtifact] = []
        leftovers.append(contentsOf: classified.related.map(\.artifact))
        leftovers.append(contentsOf: classified.developer.map(\.artifact))

        var leftoverItems: [LeftoverItem] = []
        for artifact in leftovers {
            let details = artifactMap[artifact.url]
            leftoverItems.append(
                LeftoverItem(
                    url: artifact.url,
                    appName: identity.appName,
                    bundleID: identity.bundleID,
                    sizeBytes: details?.size ?? FileManager.default.getDirectorySize(url: artifact.url),
                    score: artifact.score,
                    evidence: details?.evidence ?? artifact.evidence,
                    rawEvidence: details?.rawEvidence ?? [],
                    confidence: details?.tier ?? .possible,
                    isSelected: true
                )
            )
        }

        let report = VerificationReport(
            appName: identity.appName,
            bundleID: identity.bundleID,
            leftovers: leftovers,
            items: leftoverItems
        )
        Logger.verification.info("\(report.count, privacy: .public) leftover(s) detected")
        report.leftovers.forEach { artifact in
            Logger.verification.debug("  leftover: \(artifact.url.path, privacy: .public) score=\(artifact.score)")
        }

        return report
    }
}
