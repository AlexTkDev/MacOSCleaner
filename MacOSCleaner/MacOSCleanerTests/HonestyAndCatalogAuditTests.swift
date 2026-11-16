import XCTest
@testable import MacOSCleaner

final class HonestyAndCatalogAuditTests: XCTestCase {

    // MARK: - Stage 3: Static Network Call Audit

    func test_noNetworkAPIsOutsideUpdateChecker() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MacOSCleanerTests
            .deletingLastPathComponent() // MacOSCleaner
        let sourceDirs = ["App", "Domains", "Features", "Infrastructure", "Models", "SharedViews"]
        let forbiddenTokens = [
            "URLSession",
            "NWConnection",
            "NWListener",
            "NWBrowser",
            "NSURLConnection",
            "CFNetwork",
        ]

        var violations: [String] = []
        let fm = FileManager.default

        for dir in sourceDirs {
            let dirURL = projectRoot.appendingPathComponent(dir, isDirectory: true)
            guard let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                if fileURL.lastPathComponent == "UpdateChecker.swift" { continue }
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                for token in forbiddenTokens where content.contains(token) {
                    violations.append("\(fileURL.lastPathComponent): contains \(token)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Network APIs are strictly restricted to UpdateChecker.swift. Found: \(violations.joined(separator: ", "))"
        )
    }

    // MARK: - Stage 3: Unified Calm Risk Language

    func test_operationRiskUsesUnifiedCalmTiers() {
        XCTAssertEqual(CleanupItemManager.determineRisk(for: "~/Library/Caches/com.apple.Safari"), .safe)
        XCTAssertEqual(CleanupItemManager.determineRisk(for: "Xcode DerivedData"), .rebuildable)
        XCTAssertEqual(CleanupItemManager.determineRisk(for: "~/.gradle/caches"), .rebuildable)
        XCTAssertEqual(CleanupItemManager.determineRisk(for: "Time Machine Snapshots"), .userData)
        XCTAssertEqual(CleanupItemManager.determineRisk(for: "iOS Backups (MobileSync)"), .userData)
        XCTAssertEqual(CleanupItemManager.determineRisk(for: "~/Downloads/App.dmg"), .userData)
    }

    // MARK: - 2.4 Catalog Accuracy Invariants (Private & Public)

    func test_catalogAccuracyInvariants_noAdminOrAppDataInAutoCleanup() throws {
        // Public fallback check always runs
        for category in CleanupCategory.allCases {
            for item in EmbeddedCleanupPaths.paths(for: category) {
                XCTAssertFalse(item.path.hasPrefix("/System/"), "SIP path must never appear: \(item.path)")
            }
        }

        // Private catalog check runs when asset is present (skips on public checkout)
        try CatalogTestSupport.requirePrivateCatalog()
        for (_, appPaths) in GeneratedCleanupPaths.registry {
            for entry in appPaths.paths where entry.requiresAdmin {
                let expanded = entry.template
                XCTAssertFalse(
                    GeneratedCleanupPaths.cachePaths(for: appPaths.category).contains { $0.path == expanded },
                    "Admin path must never enter auto-cleanup: \(expanded)"
                )
            }
        }
    }
}
