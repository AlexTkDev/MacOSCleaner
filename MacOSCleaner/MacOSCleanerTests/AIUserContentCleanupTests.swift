import XCTest
@testable import MacOSCleaner

final class AIUserContentCleanupTests: XCTestCase {

    func test_aiUserContentTemplatesIncludeKnownModelStores() throws {
        try CatalogTestSupport.requirePrivateCatalog()
        let templates = GeneratedCleanupPaths.aiUserContentTemplates()
        XCTAssertTrue(templates.contains { $0.contains("ollama") })
        XCTAssertTrue(templates.contains { $0.lowercased().contains("huggingface") })
        XCTAssertTrue(templates.contains { $0.lowercased().contains("lm-studio") || $0.contains("LM Studio") })
        XCTAssertFalse(templates.isEmpty)
    }

    func test_aiUserContentTemplatesPublicFallbackKeepsHardcodedOllama() {
        PrivateCatalogStore.setOverrideForTesting(.empty)
        defer { PrivateCatalogStore.resetForTesting() }
        let templates = GeneratedCleanupPaths.aiUserContentTemplates()
        XCTAssertTrue(templates.contains("<HOME>/.local/share/ollama/models"))
    }

    func test_aiModelsExcludedFromAutoCleanCategories() {
        let categories = CleanupOptions().categories()
        XCTAssertFalse(categories.contains(.aiModels))
        XCTAssertFalse(categories.contains(.installerPackages))
        XCTAssertTrue(CleanupCategory.allCases.contains(.aiModels))
        XCTAssertTrue(CleanupCategory.allCases.contains(.installerPackages))
    }

    func test_aiModelsReviewScanEmitsOptInItemsOnly() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }

        let ollama = ctx.homeDirectory.appendingPathComponent(".ollama/models", isDirectory: true)
        try FileManager.default.createDirectory(at: ollama, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 8192).write(to: ollama.appendingPathComponent("blob.bin"))

        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var paths: [String] = []
            func append(_ p: String) { lock.lock(); defer { lock.unlock() }; paths.append(p) }
            func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return paths }
        }
        let box = Box()
        let engine = CleanupEngine(fileSystemContext: ctx)
        let results = try await engine.run(categories: [.aiModels], dryRun: true) { event in
            if case .fileItem(let path, _, _, _, let category, _) = event {
                XCTAssertEqual(category, "AI Models")
                box.append(path)
            }
        }

        XCTAssertTrue(box.snapshot().contains { $0.contains(".ollama") }, "preview=\(box.snapshot())")
        XCTAssertEqual(results.first?.removedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ollama.path))
    }
}
