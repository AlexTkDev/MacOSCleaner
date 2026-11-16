import XCTest
@testable import MacOSCleaner

final class Stage3RegressionTests: XCTestCase {

    // MARK: - 2.5 Toolchain Caches & SafetyManager.isRegenerableCachePath

    func test_isRegenerableCachePath_allowsNewToolchainsAndBlocksSensitiveDotDirs() throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let home = ctx.homePath
        let safety = SafetyManager(homeDirectory: home, fileSystemContext: ctx)

        let allowedCaches = [
            "\(home)/.cache/uv/wheels",
            "\(home)/.bun/tmp/extract",
            "\(home)/.cargo/git/db/repo",
            "\(home)/.cargo/git/checkouts/crate",
            "\(home)/.sbt/boot/scala",
            "\(home)/.cache/sbt",
            "\(home)/.gem/specs",
            "\(home)/.bundle/cache",
            "\(home)/.stack/snapshots",
            "\(home)/.claude/logs",
            "\(home)/.claude/telemetry",
            "\(home)/.continue/cache",
            "\(home)/.triton/cache",
            "\(home)/.cache/litellm",
            "\(home)/go/pkg/mod/cache/download",
        ]
        for path in allowedCaches {
            XCTAssertTrue(SafetyManager.isRegenerableCachePath(path, home: home), "Expected regenerable cache: \(path)")
            XCTAssertNoThrow(try safety.validate(url: URL(fileURLWithPath: path), policy: .cleanup), "Should allow \(path)")
        }

        let blockedNonCaches = [
            "\(home)/.config/nvim/init.vim",
            "\(home)/.local/share/Trash/file",
            "\(home)/.cache/unknown-private-store",
            "\(home)/.claude/settings.json",
            "\(home)/.claude/projects/repo",
            "\(home)/.continue/config.json",
            "\(home)/.continue/config.yaml",
            "\(home)/.sbt/1.0/plugins/build.sbt",
            "\(home)/.gem/credentials",
            "\(home)/.stack/programs/arm64-osx",
            "\(home)/.cargo/git",
            "\(home)/go/pkg/mod",
        ]
        for path in blockedNonCaches {
            XCTAssertFalse(SafetyManager.isRegenerableCachePath(path, home: home), "Must not treat as regenerable cache: \(path)")
            XCTAssertThrowsError(try safety.validate(url: URL(fileURLWithPath: path), policy: .cleanup), "Must block \(path)")
        }

        // AI model stores are opt-in user_content, never regenerable caches.
        XCTAssertFalse(SafetyManager.isRegenerableCachePath("\(home)/.cache/huggingface/hub", home: home))
        XCTAssertFalse(SafetyManager.isRegenerableCachePath("\(home)/.cache/vllm", home: home))
    }

    func test_safetyManager_allowsClineAndRooCodeCachesUnderUser() throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let home = ctx.homePath
        let safety = SafetyManager(homeDirectory: home, fileSystemContext: ctx)

        let clineCache = URL(fileURLWithPath: "\(home)/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/cache")
        let rooCache = URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/cache")
        let ideSettings = URL(fileURLWithPath: "\(home)/Library/Application Support/Code/User/settings.json")

        XCTAssertNoThrow(try safety.validate(url: clineCache, policy: .cleanup))
        XCTAssertNoThrow(try safety.validate(url: rooCache, policy: .cleanup))
        XCTAssertThrowsError(try safety.validate(url: ideSettings, policy: .cleanup))
    }

    func test_embeddedAppCachesHasNoToolchainDuplicates() {
        let appPaths = Set(EmbeddedCleanupPaths.appCaches.map(\.path))
        let dedicated = Set(
            EmbeddedCleanupPaths.gradleCacheSubpaths
            + EmbeddedCleanupPaths.flutterDartCacheSubpaths
            + EmbeddedCleanupPaths.swiftPMCacheSubpaths
            + EmbeddedCleanupPaths.carthageCacheSubpaths
            + [
                "~/Library/Caches/Homebrew",
                "~/Library/Caches/CocoaPods",
                "~/Library/Caches/JetBrains",
                "~/Library/Caches/go-build",
                "~/Library/Caches/npm",
                "~/Library/Caches/yarn",
                "~/Library/Caches/pnpm",
            ]
        )
        XCTAssertTrue(appPaths.isDisjoint(with: dedicated), "Overlap: \(appPaths.intersection(dedicated))")
    }

    func test_aiUserContentTemplatesIncludeNewModelStores() {
        PrivateCatalogStore.setOverrideForTesting(.empty)
        defer { PrivateCatalogStore.resetForTesting() }
        let templates = Set(GeneratedCleanupPaths.aiUserContentTemplates())
        XCTAssertTrue(templates.contains("<USER_CACHE>/huggingface/hub"))
        XCTAssertTrue(templates.contains("<USER_CACHE>/huggingface/datasets"))
        XCTAssertTrue(templates.contains("<USER_CACHE>/torch/hub/checkpoints"))
        XCTAssertTrue(templates.contains("<USER_CACHE>/vllm"))
        XCTAssertTrue(templates.contains("<APP_SUPPORT>/superwhisper/models"))
        XCTAssertTrue(templates.contains("<APP_SUPPORT>/com.goodsnooze.MacWhisper/models"))
    }

    // MARK: - 2.6 Project Build Artifacts Sibling Guard & .gradle/build-cache

    func test_projectBuildArtifacts_requiresSiblingMarkerForUniversalNames() throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let home = ctx.homePath
        let fm = FileManager.default

        let universalPairs: [(dir: String, marker: String)] = [
            ("dist", "package.json"),
            ("target", "Cargo.toml"),
            ("vendor", "go.mod"),
            ("venv", "requirements.txt"),
            (".venv", "pyproject.toml"),
            ("build", "Package.swift"),
            ("coverage", "tsconfig.json"),
            (".output", "package.json"),
            (".eggs", "setup.py"),
        ]

        for (dirName, marker) in universalPairs {
            let noMarkerProject = ctx.homeDirectory.appendingPathComponent("Documents/plain_\(dirName)", isDirectory: true)
            let noMarkerTarget = noMarkerProject.appendingPathComponent(dirName, isDirectory: true)
            try fm.createDirectory(at: noMarkerTarget, withIntermediateDirectories: true)
            XCTAssertFalse(
                SafetyManager.isProjectLocalBuildArtifact(noMarkerTarget.path, home: home),
                "\(dirName) without sibling marker must be rejected"
            )

            let realProject = ctx.homeDirectory.appendingPathComponent("Documents/real_\(dirName)", isDirectory: true)
            let realTarget = realProject.appendingPathComponent(dirName, isDirectory: true)
            try fm.createDirectory(at: realTarget, withIntermediateDirectories: true)
            try "marker".write(to: realProject.appendingPathComponent(marker), atomically: true, encoding: .utf8)
            XCTAssertTrue(
                SafetyManager.isProjectLocalBuildArtifact(realTarget.path, home: home),
                "\(dirName) with \(marker) must be allowed"
            )
        }
    }

    func test_projectBuildArtifacts_gradleBuildCacheDiscoveredWhenGradleIsRecent() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let fm = FileManager.default

        let project = ctx.homeDirectory.appendingPathComponent("Projects/MyAndroidApp", isDirectory: true)
        let gradleDir = project.appendingPathComponent(".gradle", isDirectory: true)
        let buildCache = gradleDir.appendingPathComponent("build-cache", isDirectory: true)
        try fm.createDirectory(at: buildCache, withIntermediateDirectories: true)
        try "plugins {}".write(to: project.appendingPathComponent("build.gradle.kts"), atomically: true, encoding: .utf8)
        try Data(repeating: 1, count: 4096).write(to: buildCache.appendingPathComponent("cache.bin"))

        // Make build-cache old (120 days), while .gradle parent stays recent.
        let oldDate = Date().addingTimeInterval(-120 * 24 * 60 * 60)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: buildCache.path)

        // Random `build-cache` without `.gradle` parent must never be touched.
        let unrelatedBuildCache = project.appendingPathComponent("build-cache", isDirectory: true)
        try fm.createDirectory(at: unrelatedBuildCache, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 4096).write(to: unrelatedBuildCache.appendingPathComponent("keep.bin"))
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelatedBuildCache.path)

        let engine = CleanupEngine(fileSystemContext: ctx)
        _ = try await engine.cleanProjectBuildArtifacts(dryRun: false, progress: nil, olderThanDays: 60)

        XCTAssertTrue(fm.fileExists(atPath: gradleDir.path), "Recent .gradle parent must remain")
        XCTAssertFalse(fm.fileExists(atPath: buildCache.path), "Old .gradle/build-cache must be cleaned")
        XCTAssertTrue(fm.fileExists(atPath: unrelatedBuildCache.path), "Unrelated build-cache must never be cleaned")
    }

    // MARK: - 2.7 Installer Packages Expansion & Zip Central Directory

    func test_installerPackages_scansMessengersHomebrewAndZipAndExcludesFromLargeFiles() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let fm = FileManager.default
        let oldDate = Date().addingTimeInterval(-45 * 24 * 60 * 60)

        // 1. Messenger image (Telegram postbox/media) + non-image media that must be ignored.
        let tgMedia = ctx.homeDirectory.appendingPathComponent("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable/account-1/postbox/media", isDirectory: true)
        try fm.createDirectory(at: tgMedia, withIntermediateDirectories: true)
        let tgDmg = tgMedia.appendingPathComponent("TelegramApp.dmg")
        let tgJpg = tgMedia.appendingPathComponent("photo.jpg")
        try Data(repeating: 1, count: 22 * 1024 * 1024).write(to: tgDmg)
        try Data(repeating: 2, count: 22 * 1024 * 1024).write(to: tgJpg)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: tgDmg.path)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: tgJpg.path)

        // 2. Homebrew downloads
        let brewDownloads = ctx.homeDirectory.appendingPathComponent("Library/Caches/Homebrew/downloads", isDirectory: true)
        try fm.createDirectory(at: brewDownloads, withIntermediateDirectories: true)
        let brewPkg = brewDownloads.appendingPathComponent("deadbeef--MyTool.pkg")
        try Data(repeating: 3, count: 22 * 1024 * 1024).write(to: brewPkg)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: brewPkg.path)

        // 3. Synthetic >50 MB ZIP with `.app/` in Central Directory + non-installer ZIP.
        let downloads = ctx.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let installerZip = downloads.appendingPathComponent("MyApp-1.0.zip")
        try Self.writeSyntheticZip(to: installerZip, entryName: "MyApp.app/Contents/Info.plist", totalSizeBytes: 110 * 1024 * 1024)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: installerZip.path)

        let plainZip = downloads.appendingPathComponent("Archive.zip")
        try Self.writeSyntheticZip(to: plainZip, entryName: "docs/readme.txt", totalSizeBytes: 110 * 1024 * 1024)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: plainZip.path)

        // SafetyManager allows new installer sources
        XCTAssertTrue(SafetyManager.isReviewableInstallerLeaf(tgDmg.path, home: ctx.homePath))
        XCTAssertTrue(SafetyManager.isReviewableInstallerLeaf(brewPkg.path, home: ctx.homePath))
        XCTAssertTrue(SafetyManager.isReviewableInstallerLeaf(installerZip.path, home: ctx.homePath))
        XCTAssertFalse(SafetyManager.isReviewableInstallerLeaf(tgJpg.path, home: ctx.homePath))

        let engine = CleanupEngine(fileSystemContext: ctx)

        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private var paths: [String] = []
            func append(_ p: String) { lock.withLock { paths.append(p) } }
            func snapshot() -> [String] { lock.withLock { paths } }
        }

        let installerBox = Collector()
        _ = try await engine.run(categories: [.installerPackages], dryRun: true) { event in
            if case .fileItem(let path, _, _, _, _, _, _, _, _) = event {
                installerBox.append(path)
            }
        }
        let installerPaths = installerBox.snapshot()
        XCTAssertTrue(installerPaths.contains(tgDmg.path))
        XCTAssertTrue(installerPaths.contains(brewPkg.path))
        XCTAssertTrue(installerPaths.contains(installerZip.path))
        XCTAssertFalse(installerPaths.contains(tgJpg.path))
        XCTAssertFalse(installerPaths.contains(plainZip.path))

        // Large files must skip installerZip so one file belongs to one category.
        let largeBox = Collector()
        _ = try await engine.run(categories: [.largeFiles], dryRun: true) { event in
            if case .fileItem(let path, _, _, _, _, _, _, _, _) = event {
                largeBox.append(path)
            }
        }
        let largePaths = largeBox.snapshot()
        XCTAssertFalse(largePaths.contains(installerZip.path))
        XCTAssertTrue(largePaths.contains(plainZip.path))
    }

    // MARK: - 2.8 Apple Intelligence Read-Only Storage Overview

    func test_appleIntelligenceStorageReader_handlesEPERMWithEstimateAndNoCleanupCategory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AIStorageTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.appendingPathComponent("RestrictedBase").path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let readableAsset = tempDir.appendingPathComponent("MagicCleanup", isDirectory: true)
        try FileManager.default.createDirectory(at: readableAsset, withIntermediateDirectories: true)
        try Data(repeating: 5, count: 16_384).write(to: readableAsset.appendingPathComponent("asset.bin"))

        let restrictedBase = tempDir.appendingPathComponent("RestrictedBase", isDirectory: true)
        try FileManager.default.createDirectory(at: restrictedBase, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restrictedBase.path)

        let snapshot = AppleIntelligenceStorageReader.inspect(
            components: [
                .init(id: "magic", titleKey: "settings_ai_comp_photos_cleanup", path: readableAsset.path),
            ],
            baseModelPath: restrictedBase.path
        )

        XCTAssertEqual(snapshot.components.count, 1)
        XCTAssertGreaterThan(snapshot.totalReadableBytes, 0)
        XCTAssertTrue(snapshot.isBaseModelAccessRestricted)
        XCTAssertNil(snapshot.baseModelReadableBytes)

        // Ensure Apple Intelligence system models are never part of CleanupCategory.
        XCTAssertFalse(CleanupCategory.allCases.contains { $0.rawValue.contains("apple_intelligence") })
        XCTAssertFalse(CleanupOptions().categories().contains(.aiModels))
    }

    // MARK: - Helpers

    private static func writeSyntheticZip(to url: URL, entryName: String, totalSizeBytes: Int) throws {
        let nameData = Data(entryName.utf8)
        var cd = Data()
        // Central Directory Header (46 bytes + name)
        cd.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // signature
        cd.append(contentsOf: [20, 0, 20, 0, 0, 0, 0, 0]) // versions, flags, method
        cd.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // time/date/crc
        cd.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // sizes
        cd.append(contentsOf: [UInt8(nameData.count & 0xff), UInt8((nameData.count >> 8) & 0xff)])
        cd.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // extra, comment, disk, int attr
        cd.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // ext attr, local header offset
        cd.append(nameData)

        let cdOffset = UInt32(totalSizeBytes)
        let cdSize = UInt32(cd.count)
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // signature
        eocd.append(contentsOf: [0, 0, 0, 0]) // disk numbers
        eocd.append(contentsOf: [1, 0, 1, 0]) // entries on disk / total
        eocd.append(contentsOf: withUnsafeBytes(of: cdSize.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: cdOffset.littleEndian) { Array($0) })
        eocd.append(contentsOf: [0, 0]) // comment length

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(totalSizeBytes))
        try handle.seek(toOffset: UInt64(totalSizeBytes))
        try handle.write(contentsOf: cd)
        try handle.write(contentsOf: eocd)
    }
}
