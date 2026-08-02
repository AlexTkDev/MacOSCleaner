import XCTest
@testable import MacOSCleaner

/// Maintainer live audit: resolve installed apps, score residuals, flag sparse results.
/// Skips when `/Applications` is empty (CI without a desktop install).
final class LiveResidualAuditTests: XCTestCase {
    func test_live_audit_installedApps_and_keyRecalls() async throws {
        let fm = FileManager.default
        let appRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
        ]
        var appURLs: [URL] = []
        for root in appRoots {
            guard let kids = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            appURLs.append(contentsOf: kids.filter { $0.pathExtension == "app" })
        }
        // Homebrew Cellar IDLE / Python Launcher style
        for cellar in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
            let cellarURL = URL(fileURLWithPath: cellar, isDirectory: true)
            guard let formulae = try? fm.contentsOfDirectory(
                at: cellarURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for formula in formulae {
                guard let versions = try? fm.contentsOfDirectory(
                    at: formula,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for version in versions {
                    guard let apps = try? fm.contentsOfDirectory(
                        at: version,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    appURLs.append(contentsOf: apps.filter { $0.pathExtension == "app" })
                }
            }
        }

        appURLs = Array(Set(appURLs)).sorted { $0.path < $1.path }
        if appURLs.isEmpty {
            throw XCTSkip("No applications found for live residual audit")
        }

        let safety = SafetyManager()
        let probe = EvidenceProbe()
        let collector = CandidateCollector(fileSystemContext: .production)
        let ruleRegistry = ApplicationRuleRegistry.createDefault()
        let home = fm.homeDirectoryForCurrentUser.path

        var sparse: [(String, Int, Int)] = []
        var asAppSupportRootTiers: [ConfidenceTier] = []
        var anydeskKept = false
        var chromeBareGoogle = false

        for appURL in appURLs {
            let identity = await AppIdentity.resolve(from: appURL)
            let collection = await collector.collectDetailed(identity: identity, mode: .balanced)
            let rule = await ruleRegistry.bestRule(for: identity)

            var kept = 0
            for url in collection.candidates {
                // Skip the app bundle itself from residual counts.
                if NormalizedPath.key(url) == NormalizedPath.key(identity.bundleURL) { continue }
                var evidence = await probe.probe(url: url, identity: identity)
                if collection.catalogPaths.contains(where: { NormalizedPath.key($0) == NormalizedPath.key(url) }) {
                    evidence.insert(.knownCatalog)
                }
                let ruleScore = rule.evidence(for: url, identity: identity).reduce(0) { $0 + $1.weight }
                let assessment = ConfidenceEngine.assess(evidence, ruleScore: ruleScore, identity: identity)
                let safetyOK = (try? safety.validate(url: url, policy: .uninstall)) != nil
                guard assessment.tier >= .possible, safetyOK else { continue }
                kept += 1

                let path = url.path
                let leaf = url.lastPathComponent
                let parent = url.deletingLastPathComponent().lastPathComponent
                if identity.bundleID == "com.google.android.studio",
                   parent == "Google",
                   leaf.lowercased().hasPrefix("androidstudio") {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        asAppSupportRootTiers.append(assessment.tier)
                    }
                }
                if identity.bundleID == "com.philandro.anydesk", path.hasSuffix("/.anydesk") {
                    anydeskKept = true
                }
                if identity.bundleID == "com.google.Chrome",
                   path == "\(home)/Library/Application Support/Google"
                    || path == "\(home)/Library/Caches/Google" {
                    chromeBareGoogle = true
                }
            }

            if kept < 2 {
                sparse.append((identity.appName, collection.candidates.count, kept))
            }
        }

        print("=== Live residual audit: \(appURLs.count) apps, sparse(kept<2)=\(sparse.count) ===")
        for (name, candidates, kept) in sparse.prefix(40) {
            print("  sparse \(name): candidates=\(candidates) kept=\(kept)")
        }

        // Key recalls (skip if app not installed).
        if fm.fileExists(atPath: "/Applications/Android Studio.app") {
            XCTAssertFalse(asAppSupportRootTiers.isEmpty, "Android Studio Application Support roots missing")
            XCTAssertTrue(
                asAppSupportRootTiers.allSatisfy { $0 >= .veryLikely },
                "Android Studio App Support roots must be ≥ veryLikely, got \(asAppSupportRootTiers)"
            )
        }
        if fm.fileExists(atPath: "/Applications/AnyDesk.app"),
           fm.fileExists(atPath: home + "/.anydesk") {
            XCTAssertTrue(anydeskKept, "AnyDesk ~/.anydesk must be kept")
        }
        if fm.fileExists(atPath: "/Applications/Google Chrome.app") {
            XCTAssertFalse(chromeBareGoogle, "Chrome must not keep bare Google vendor root")
        }
    }
}
