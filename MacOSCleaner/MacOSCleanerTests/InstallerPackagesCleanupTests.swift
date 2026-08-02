import XCTest
@testable import MacOSCleaner

final class InstallerPackagesCleanupTests: XCTestCase {

    func test_installerPackagesReviewScanEmitsOptInItems() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }

        let downloads = ctx.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let dmg = downloads.appendingPathComponent("App-Installer.dmg")
        try Data(repeating: 9, count: 25 * 1024 * 1024).write(to: dmg)
        let old = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dmg.path)

        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var paths: [String] = []
            func append(_ p: String) { lock.lock(); defer { lock.unlock() }; paths.append(p) }
            func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return paths }
        }
        let box = Box()
        let engine = CleanupEngine(fileSystemContext: ctx)
        let results = try await engine.run(categories: [.installerPackages], dryRun: true) { event in
            if case .fileItem(let path, _, _, _, let category, _) = event {
                XCTAssertEqual(category, "Installer Packages")
                box.append(path)
            }
        }

        XCTAssertTrue(box.snapshot().contains { $0.hasSuffix(".dmg") }, "preview=\(box.snapshot())")
        XCTAssertEqual(results.first?.removedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dmg.path))
    }

    func test_safetyAllowsReviewableInstallerLeaf() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafetyInstaller-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        let dmg = home.appendingPathComponent("Downloads/Foo.dmg")
        try Data([1]).write(to: dmg)

        let safety = SafetyManager(homeDirectory: home.path)
        XCTAssertNoThrow(try safety.validate(url: dmg, policy: .cleanup))
    }
}
