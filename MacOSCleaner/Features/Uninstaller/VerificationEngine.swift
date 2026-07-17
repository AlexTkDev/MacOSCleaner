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

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        codesignCache: CodesignCache = CodesignCache(),
        plistCache: PlistContentCache = PlistContentCache(),
        thresholds: ScoreThresholds = .default,
        weights: ScoringWeights = .default,
        ruleRegistry: ApplicationRuleRegistry = ApplicationRuleRegistry.createDefault()
    ) {
        self.commandRunner = commandRunner
        self.codesignCache = codesignCache
        self.plistCache = plistCache
        self.thresholds = thresholds
        self.weights = weights
        self.ruleRegistry = ruleRegistry
    }

    public func verify(identity: AppIdentity) async -> VerificationReport {
        Logger.verification.info("Verifying '\(identity.appName, privacy: .public)' after uninstall")

        let collector = CandidateCollector(fileManager: .default, commandRunner: commandRunner)
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
        let rule = await ruleRegistry.bestRule(for: identity)

        for url in candidates {
            let evidence = await probe.probe(url: url, identity: identity)
            let ruleEvidence = rule.evidence(for: url, identity: identity)
            guard !evidence.isEmpty || !ruleEvidence.isEmpty else { continue }

            let artifactEvidence = evidence.artifactEvidence(weights: weights) + ruleEvidence
            let score = artifactEvidence.reduce(0) { $0 + $1.weight }

            artifacts.append(
                ScoredArtifact(url: url, score: score, evidence: artifactEvidence)
            )
        }

        let classified = ArtifactClassifier.classifyBatch(artifacts, thresholds: thresholds)

        var leftovers: [ScoredArtifact] = []
        leftovers.append(contentsOf: classified.related.map(\.artifact))
        leftovers.append(contentsOf: classified.developer.map(\.artifact))

        let report = VerificationReport(leftovers: leftovers)
        Logger.verification.info("\(report.count, privacy: .public) leftover(s) detected")
        report.leftovers.forEach { artifact in
            Logger.verification.debug("  leftover: \(artifact.url.path, privacy: .public) score=\(artifact.score)")
        }

        return report
    }
}
