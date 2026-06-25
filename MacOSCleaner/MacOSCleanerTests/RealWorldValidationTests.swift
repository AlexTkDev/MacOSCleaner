import Testing
import Foundation
@testable import MacOSCleaner

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
struct RealWorldValidationTests {

    private func loadFixture(_ name: String) throws -> BaselineFixture {
        // Use the test bundle's resource path
        let bundle = Bundle(identifier: "com.macos-cleaner.MacOSCleanerTests") ?? Bundle.main
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw TestError.fixtureNotFound(name)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BaselineFixture.self, from: data)
    }

    private func runFullPipeline(for identity: AppIdentity) async -> (related: [ClassifiedArtifact], developer: [ClassifiedArtifact], ignored: [ClassifiedArtifact]) {
        let collector = CandidateCollector(fileManager: .default, commandRunner: CommandRunner())
        let candidates = await collector.collect(identity: identity)

        let probe = EvidenceProbe(commandRunner: CommandRunner(), codesignCache: CodesignCache(), plistCache: PlistContentCache())

        var artifacts: [ScoredArtifact] = []
        for url in candidates {
            let evidence = await probe.probe(url: url, identity: identity)
            guard !evidence.isEmpty else { continue }

            let artifactEvidence = evidence.artifactEvidence(weights: .default)
            let score = artifactEvidence.reduce(0) { $0 + $1.weight }

            artifacts.append(ScoredArtifact(url: url, score: score, evidence: artifactEvidence))
        }

        return ArtifactClassifier.classifyBatch(artifacts, thresholds: .default)
    }

    @Test("Postman baseline", .tags(.baseline))
    func testPostmanBaseline() async throws {
        let fixture = try loadFixture("Postman")
        let identity = AppIdentity(
            bundleID: fixture.bundleID,
            appName: fixture.app,
            bundleName: fixture.app,
            bundleVersion: "1.0",
            executableName: fixture.app,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(fixture.app).app"),
            isAppStore: false,
            isSandboxed: false,
            isAdHocSigned: false,
            vendorNames: [],
            helperNames: [],
            frameworkNames: [],
            xpcServiceNames: [],
            plugInNames: [],
            isElectron: true,
            isJetBrains: false,
            isFlutter: false,
            isJava: false,
            isQt: false,
            isDocker: false
        )

        let result = await runFullPipeline(for: identity)

        for path in fixture.mustFind {
            let expanded = NSString(string: path).expandingTildeInPath
            #expect(result.related.contains { $0.artifact.url.path.hasSuffix(expanded) } ||
                    result.developer.contains { $0.artifact.url.path.hasSuffix(expanded) },
                    "Must find: \(path)")
        }

        for pattern in fixture.mustNotFind {
            #expect((result.related + result.developer).allSatisfy { !$0.artifact.url.path.contains(pattern) },
                    "Must not find: \(pattern)")
        }

        let minScore = min(result.related.map(\.artifact.score).min() ?? 100,
                          result.developer.map(\.artifact.score).min() ?? 100)
        #expect(minScore >= fixture.scoreFloor, "Score floor \(fixture.scoreFloor) not met (min was \(minScore))")
    }

    @Test("Cursor baseline", .tags(.baseline))
    func testCursorBaseline() async throws {
        let fixture = try loadFixture("Cursor")
        let identity = AppIdentity(
            bundleID: fixture.bundleID,
            appName: fixture.app,
            bundleName: fixture.app,
            bundleVersion: "1.0",
            executableName: fixture.app,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(fixture.app).app"),
            isAppStore: false,
            isSandboxed: false,
            isAdHocSigned: false,
            vendorNames: [],
            helperNames: [],
            frameworkNames: ["Electron Framework"],
            xpcServiceNames: [],
            plugInNames: [],
            isElectron: true,
            isJetBrains: false,
            isFlutter: false,
            isJava: false,
            isQt: false,
            isDocker: false
        )

        let result = await runFullPipeline(for: identity)

        for path in fixture.mustFind {
            let expanded = NSString(string: path).expandingTildeInPath
            #expect(result.related.contains { $0.artifact.url.path.hasSuffix(expanded) } ||
                    result.developer.contains { $0.artifact.url.path.hasSuffix(expanded) },
                    "Must find: \(path)")
        }

        for pattern in fixture.mustNotFind {
            #expect((result.related + result.developer).allSatisfy { !$0.artifact.url.path.contains(pattern) },
                    "Must not find: \(pattern)")
        }
    }
}

enum TestError: Error {
    case fixtureNotFound(String)
}

extension Tag {
    @Tag static var baseline: Tag
}
