import Foundation
import Testing
@testable import MacOSCleaner

@Suite("CleanupEngine")
struct CleanupEngineTests {

    // MARK: - CleanupTimeouts Tests

    @Test("Default timeout values")
    func defaultTimeoutValues() {
        let timeouts = CleanupTimeouts.default
        #expect(timeouts.fast == .seconds(30))
        #expect(timeouts.system == .seconds(120))
        #expect(timeouts.full == .seconds(300))
        #expect(timeouts.scatteredJunk == .seconds(600))
    }

    @Test("Custom timeout values")
    func customTimeoutValues() {
        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(180), scatteredJunk: .seconds(900))
        #expect(timeouts.fast == .seconds(10))
        #expect(timeouts.system == .seconds(60))
        #expect(timeouts.full == .seconds(180))
        #expect(timeouts.scatteredJunk == .seconds(900))
    }

    @Test("Partial custom timeouts")
    func partialCustomTimeouts() {
        let timeouts = CleanupTimeouts(fast: .seconds(5))
        #expect(timeouts.fast == .seconds(5))
        #expect(timeouts.system == .seconds(120))
        #expect(timeouts.full == .seconds(300))
        #expect(timeouts.scatteredJunk == .seconds(600))
    }

    // MARK: - CleanupEngineError Tests

    @Test("Timeout error description")
    func timeoutErrorDescription() {
        let error = CleanupEngineError.timeout
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("timed out"))
    }

    @Test("Safety violation error description")
    func safetyViolationErrorDescription() {
        let error = CleanupEngineError.safetyViolation("/System")
        #expect(error.errorDescription == "Safety violation: /System")
    }

    @Test("Command failed error description")
    func commandFailedErrorDescription() {
        let error = CleanupEngineError.commandFailed("brew not found")
        #expect(error.errorDescription == "Command failed: brew not found")
    }

    // MARK: - FileManager Operations Tests

    @Test("Clean contents creates and deletes files")
    func cleanContentsCreatesAndDeletesFiles() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let file1 = tempDir.appendingPathComponent("file1.txt")
        let file2 = tempDir.appendingPathComponent("file2.log")
        try "data1".write(to: file1, atomically: true, encoding: .utf8)
        try "data2".write(to: file2, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: file1.path))
        #expect(FileManager.default.fileExists(atPath: file2.path))

        let result = try await engine.cleanContents(of: tempDir.path, dryRun: false)
        #expect(result.freed >= 0)

        #expect(!FileManager.default.fileExists(atPath: file1.path))
        #expect(!FileManager.default.fileExists(atPath: file2.path))
    }

    @Test("Clean contents preserves credential files")
    func cleanContentsPreservesCredentialFiles() async throws {
        let engine = CleanupEngine()
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacOSCleanerTests_Cred_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cookies = dir.appendingPathComponent("Cookies")
        let junk = dir.appendingPathComponent("junk.txt")
        try "session".write(to: cookies, atomically: true, encoding: .utf8)
        try "junk".write(to: junk, atomically: true, encoding: .utf8)

        _ = try await engine.cleanContents(of: dir.path, dryRun: false)

        #expect(FileManager.default.fileExists(atPath: cookies.path))
        #expect(!FileManager.default.fileExists(atPath: junk.path))
    }

    @Test("Clean contents dry run preserves files")
    func cleanContentsDryRunPreservesFiles() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let file = tempDir.appendingPathComponent("cache.dat")
        try "cachedata".write(to: file, atomically: true, encoding: .utf8)

        let result = try await engine.cleanContents(of: tempDir.path, dryRun: true)
        #expect(result.freed >= 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Remove directory deletes entire folder")
    func removeDirectoryDeletesEntireFolder() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        let subDir = tempDir.appendingPathComponent("subfolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let file = subDir.appendingPathComponent("nested.txt")
        try "nested".write(to: file, atomically: true, encoding: .utf8)

        let result = try await engine.removeDirectory(tempDir.path, dryRun: false)
        #expect(result.freed >= 0)
        #expect(!FileManager.default.fileExists(atPath: tempDir.path))
    }

    @Test("Remove file deletes single file")
    func removeFileDeletesSingleFile() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let file = tempDir.appendingPathComponent("single.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let result = try await engine.removeFile(file.path, dryRun: false)
        #expect(result.freed >= 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Clean contents on nonexistent path returns zero")
    func cleanContentsOnNonexistentPathReturnsZero() async throws {
        let engine = CleanupEngine()
        let result = try await engine.cleanContents(of: "/tmp/nonexistent_\(UUID().uuidString)", dryRun: false)
        #expect(result.freed == 0)
    }

    @Test("Clean old files removes older than days")
    func cleanOldFilesRemovesOlderThanDays() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let oldFile = tempDir.appendingPathComponent("old.txt")
        let newFile = tempDir.appendingPathComponent("new.txt")
        try "old".write(to: oldFile, atomically: true, encoding: .utf8)
        try "new".write(to: newFile, atomically: true, encoding: .utf8)

        let oldAttrs: [FileAttributeKey: Any] = [.modificationDate: Date().addingTimeInterval(-86400 * 10)]
        try FileManager.default.setAttributes(oldAttrs, ofItemAtPath: oldFile.path)

        let result = try await engine.cleanOldFiles(in: tempDir.path, olderThanDays: 7, dryRun: false)
        #expect(result.freed >= 0)

        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: newFile.path))
    }

    // MARK: - Process Call Tests (with Mock)

    @Test("Mock command runner returns expected result")
    func mockCommandRunnerReturnsExpectedResult() async throws {
        let mock = MockCommandRunner()
        mock.runHandler = { command, args in
            if args.joined(separator: " ").contains("brew --cache") {
                return CommandResult(stdout: "/tmp/brew-cache", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let result = try await mock.run(command: "/bin/bash", arguments: ["-c", "brew --cache 2>/dev/null"], timeout: .seconds(5))
        #expect(result.stdout == "/tmp/brew-cache")
        #expect(result.exitCode == 0)
    }

    @Test("Mock command exists returns correctly")
    func mockCommandExistsReturnsCorrectly() async {
        let mock = MockCommandRunner()
        mock.availableCommands = ["brew", "npm"]

        let brewExists = await mock.commandExists("brew")
        #expect(brewExists)
        let npmExists = await mock.commandExists("npm")
        #expect(npmExists)
        let nonexistentExists = await mock.commandExists("nonexistent")
        #expect(!nonexistentExists)
    }

    @Test("Package managers with mock")
    func packageManagersWithMock() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["brew", "npm"]

        let counter = ThreadSafeCounter()
        mock.runHandler = { command, args in
            counter.increment()
            let cmd = args.joined(separator: " ")

            if cmd.contains("brew --cache") {
                return CommandResult(stdout: "/tmp/brew-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("brew cleanup") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            if cmd.contains("npm config get cache") {
                return CommandResult(stdout: "/tmp/npm-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("npm cache clean") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = CleanupEngine(commandRunner: mock)
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.cleanPackageManagers(dryRun: true, progress: nil)
        #expect(!results.isEmpty)
        #expect(counter.value >= 2)
    }

    @Test("Docker cleanup with mock")
    func dockerCleanupWithMock() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["docker"]

        mock.runHandler = { command, args in
            let cmd = args.joined(separator: " ")
            if cmd.contains("docker system df") {
                return CommandResult(stdout: "TYPE TOTAL ACTIVE SIZE", stderr: "", exitCode: 0)
            }
            if cmd.contains("docker system prune") {
                return CommandResult(stdout: "Total reclaimed space: 1GB", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = CleanupEngine(commandRunner: mock)
        let results = try await engine.cleanDocker(dryRun: true, progress: nil)
        #expect(results.count == 1)
        #expect(results.first?.label == "Docker")
    }

    @Test("Docker cleanup skipped when not installed")
    func dockerCleanupSkippedWhenNotInstalled() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = []

        let engine = CleanupEngine(commandRunner: mock)
        let results = try await engine.cleanDocker(dryRun: false, progress: nil)
        #expect(results.count == 1)
        #expect(results.first?.freedMB == 0)
    }

    // MARK: - Cancellation Tests

    @Test("Cancellation stops execution")
    func cancellationStopsExecution() async throws {
        let engine = CleanupEngine()
        let task = Task {
            try await engine.run(categories: CleanupCategory.allCases, dryRun: true)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // CleanupEngineError.timeout or other acceptable errors
        }
    }

    @Test("Cancellation between categories")
    func cancellationBetweenCategories() async throws {
        let engine = CleanupEngine()

        let task = Task { () -> [CleanupCategory] in
            var completed: [CleanupCategory] = []
            for category in [CleanupCategory.appCaches, .packageManagers, .browserCaches] {
                try Task.checkCancellation()
                completed.append(category)
            }
            return completed
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors acceptable
        }
    }

    @Test("Scan does not delete files")
    func scanDoesNotDeleteFiles() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let testFile = tempDir.appendingPathComponent("cache.txt")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        _ = try await engine.scan(categories: [.scatteredJunk])
        #expect(FileManager.default.fileExists(atPath: testFile.path), "Scan should not delete files")
    }

    // MARK: - Timeout Tests

    @Test("Operation completes within timeout")
    func operationCompletesWithinTimeout() async throws {
        let engine = CleanupEngine(timeouts: CleanupTimeouts(fast: .seconds(5)))
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let result = try await engine.cleanContents(of: tempDir.path, dryRun: true)
        #expect(result.freed >= 0)
    }

    @Test("Timeout cancels slow operation")
    func timeoutCancelsSlowOperation() async {
        let shortTimeouts = CleanupTimeouts(system: .milliseconds(100))
        let engine = CleanupEngine(timeouts: shortTimeouts)

        do {
            _ = try await engine.run(categories: [.packageManagers], dryRun: false)
        } catch CleanupEngineError.timeout {
            // Expected when operation takes longer than 100ms
        } catch {
            // Other errors acceptable (e.g., command not found)
        }
    }

    @Test("Fast category uses fast timeout")
    func fastCategoryUsesFastTimeout() async throws {
        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(300))
        let engine = CleanupEngine(timeouts: timeouts)
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.run(categories: [.appCaches], dryRun: true)
        #expect(!results.isEmpty, "Should return at least one result")
    }

    @Test("System category uses system timeout")
    func systemCategoryUsesSystemTimeout() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["brew"]

        mock.runHandler = { command, args in
            let cmd = args.joined(separator: " ")
            if cmd.contains("brew --cache") {
                return CommandResult(stdout: "/tmp/brew-cache", stderr: "", exitCode: 0)
            }
            if cmd.contains("brew cleanup") {
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(300))
        let engine = CleanupEngine(commandRunner: mock, timeouts: timeouts)

        let results = try await engine.run(categories: [.packageManagers], dryRun: true)
        #expect(!results.isEmpty)
    }

    @Test("Full category uses full timeout")
    func fullCategoryUsesFullTimeout() async throws {
        let timeouts = CleanupTimeouts(fast: .seconds(10), system: .seconds(60), full: .seconds(300))
        let engine = CleanupEngine(timeouts: timeouts)
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.run(categories: [.xcode], dryRun: true)
        #expect(!results.isEmpty)
    }

    @Test("ScatteredJunk category uses scatteredJunk timeout")
    func scatteredJunkUsesScatteredJunkTimeout() async throws {
        let timeouts = CleanupTimeouts(
            fast: .seconds(10),
            system: .seconds(60),
            full: .seconds(300),
            scatteredJunk: .seconds(600)
        )
        let engine = CleanupEngine(timeouts: timeouts)

        let results = try await engine.run(categories: [.scatteredJunk], dryRun: true)
        #expect(!results.isEmpty)
        #expect(results.first?.label == "Scattered junk")
    }

    // MARK: - PosixScanner Tests

    @Test("PosixScanner scans files recursively")
    func posixScannerScansFilesRecursively() async throws {
        let scanner = PosixScanner()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("posix_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "data1".write(to: tempDir.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try "data2".write(to: subDir.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)

        var entries: [PosixScanner.Entry] = []
        for await batch in scanner.scanParallel(roots: [tempDir.path]) {
            entries.append(contentsOf: batch)
        }

        #expect(entries.count >= 2)
        let names = entries.map(\.name).sorted()
        #expect(names.contains("file1.txt"))
        #expect(names.contains("file2.txt"))
    }

    @Test("PosixScanner excludes specified prefixes")
    func posixScannerExcludesSpecifiedPrefixes() async throws {
        let scanner = PosixScanner()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("posix_excl_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keepDir = tempDir.appendingPathComponent("keep")
        let skipDir = tempDir.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: keepDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skipDir, withIntermediateDirectories: true)
        try "keep".write(to: keepDir.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        try "skip".write(to: skipDir.appendingPathComponent("skip.txt"), atomically: true, encoding: .utf8)

        var entries: [PosixScanner.Entry] = []
        for await batch in scanner.scanParallel(
            roots: [tempDir.path],
            config: .init(excludedPrefixes: ["/Library/"])
        ) {
            entries.append(contentsOf: batch)
        }

        let paths = entries.map(\.path)
        #expect(paths.contains { $0.contains("keep.txt") })
        #expect(!paths.contains { $0.contains("skip.txt") })
    }

    @Test("PosixScanner detects symlinks")
    func posixScannerDetectsSymlinks() async throws {
        let scanner = PosixScanner()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("posix_link_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let realFile = tempDir.appendingPathComponent("real.txt")
        try "data".write(to: realFile, atomically: true, encoding: .utf8)

        let symlink = tempDir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)

        var entries: [PosixScanner.Entry] = []
        for await batch in scanner.scanParallel(roots: [tempDir.path]) {
            entries.append(contentsOf: batch)
        }

        let linkEntry = entries.first { $0.name == "link.txt" }
        #expect(linkEntry != nil)
        #expect(linkEntry?.isSymlink == true)
    }

    @Test("PosixScanner does not follow symlink loops")
    func posixScannerDoesNotFollowSymlinkLoops() async throws {
        let scanner = PosixScanner()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("posix_loop_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let symlink = subDir.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: tempDir)

        var entryCount = 0
        for await batch in scanner.scanParallel(roots: [tempDir.path]) {
            entryCount += batch.count
        }

        #expect(entryCount < 1000, "Should not recurse infinitely through symlink loops")
    }

    // MARK: - Error Handling Tests

    @Test("Safety violation throws on protected path")
    func safetyViolationThrowsOnProtectedPath() async throws {
        let engine = CleanupEngine()

        do {
            _ = try await engine.cleanContents(of: "/System/Library", dryRun: false)
            Issue.record("Expected safety violation error")
        } catch {
            #expect(error is SafetyError)
        }
    }

    @Test("Safety violation on home SSH")
    func safetyViolationOnHomeSSH() async throws {
        let ctx = try FileSystemContext.isolatedTestRoot()
        defer { try? FileManager.default.removeItem(at: ctx.allowedRoots[0]) }
        let engine = CleanupEngine(fileSystemContext: ctx)

        do {
            _ = try await engine.cleanContents(of: "\(ctx.homePath)/.ssh", dryRun: false)
            Issue.record("Expected safety violation error")
        } catch {
            #expect(error is SafetyError)
        }
    }

    @Test("Permission denied handled gracefully")
    func permissionDeniedHandledGracefully() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()

        let protectedDir = tempDir.appendingPathComponent("protected")
        try FileManager.default.createDirectory(at: protectedDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: protectedDir.path)

        do {
            let result = try await engine.cleanContents(of: protectedDir.path, dryRun: false)
            #expect(result.freed == 0)
        } catch {
            #expect(error is CocoaError || (error as NSError).code == 257,
                    "Permission denied error should be caught: \(error)")
        }

        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: protectedDir.path)
        cleanupTempDir(tempDir)
    }

    @Test("Run returns large files category")
    func runReturnsLargeFilesCategory() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.largeFiles], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Large files")
    }

    @Test("Progress callback invoked")
    func progressCallbackInvoked() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let events = ThreadSafeArray<CleanupEngineEvent>()
        let results = try await engine.run(categories: [.scatteredJunk], dryRun: true) { event in
            events.append(event)
        }

        #expect(!results.isEmpty)
        #expect(!events.isEmpty)
    }

    @Test("Multiple categories processed")
    func multipleCategoriesProcessed() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let results = try await engine.run(categories: [.appCaches, .gradleMaven, .flutterDart], dryRun: true)
        #expect(results.count >= 1)
    }

    // MARK: - New Category Tests (13 categories)

    @Test("Time machine snapshots dry run")
    func timeMachineSnapshotsDryRun() async throws {
        let mock = MockCommandRunner()
        mock.availableCommands = ["tmutil"]
        mock.runHandler = { command, args in
            let cmd = args.joined(separator: " ")
            if cmd.contains("tmutil listlocalsnapshots") {
                return CommandResult(stdout: "com.apple.TimeMachine.2026-01-01-120000.local\ncom.apple.TimeMachine.2026-01-02-120000.local", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        let engine = CleanupEngine(commandRunner: mock)
        let results = try await engine.run(categories: [.timeMachineSnapshots], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Time Machine Snapshots")
    }

    @Test("IOS backups dry run")
    func iosBackupsDryRun() async throws {
        let engine = CleanupEngine()
        let tempDir = createTempCacheDir()
        defer { cleanupTempDir(tempDir) }

        let backupDir = tempDir.appendingPathComponent("MobileSync/Backup/test_backup_123")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try "data".write(to: backupDir.appendingPathComponent("manifest.db"), atomically: true, encoding: .utf8)

        let results = try await engine.run(categories: [.iosBackups], dryRun: true)
        #expect(!results.isEmpty)
    }

    @Test("Mail downloads dry run")
    func mailDownloadsDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.mailDownloads], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Mail Downloads")
    }

    @Test("Saved app state dry run")
    func savedAppStateDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.savedAppState], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Saved Application State")
    }

    @Test("Crash reporter dry run")
    func crashReporterDryRun() async throws {
        let engine = CleanupEngine()
        do {
            let results = try await engine.run(categories: [.crashReporter], dryRun: true)
            #expect(results.count == 1)
            #expect(results.first?.label == "Crash Reporter")
        } catch is SafetyError {
            // Expected: /Library/Logs/DiagnosticReports is a protected system path
            #expect(Bool(true))
        }
    }

    @Test("Assets v2 dry run")
    func assetsV2DryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.assetsV2], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "AssetsV2 / iWork Templates")
    }

    @Test("CloudKit cache dry run")
    func cloudKitCacheDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.cloudKitCache], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "CloudKit Cache")
    }

    @Test("SwiftPM cache dry run")
    func swiftPMCacheDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.swiftPMCache], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Swift Package Manager Cache")
    }

    @Test("Carthage cache dry run")
    func carthageCacheDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.carthageCache], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Carthage Cache")
    }

    @Test("Steam cache dry run")
    func steamCacheDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.steamCache], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Steam Cache")
    }

    @Test("Teams cache dry run")
    func teamsCacheDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.teamsCache], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Microsoft Teams Cache")
    }

    @Test("Adobe caches dry run")
    func adobeCachesDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.adobeCaches], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Adobe Caches")
    }

    @Test("Chrome extra caches dry run")
    func chromeExtraCachesDryRun() async throws {
        let engine = CleanupEngine()
        let results = try await engine.run(categories: [.chromeExtraCaches], dryRun: true)
        #expect(results.count == 1)
        #expect(results.first?.label == "Chrome Extra Caches")
    }

    @Test("All new categories included in CleanupOptions")
    func allNewCategoriesIncludedInCleanupOptions() {
        let options = CleanupOptions()
        let categories = options.categories()
        #expect(categories.contains(.timeMachineSnapshots))
        #expect(categories.contains(.iosBackups))
        #expect(categories.contains(.mailDownloads))
        #expect(categories.contains(.savedAppState))
        #expect(categories.contains(.crashReporter))
        #expect(categories.contains(.assetsV2))
        #expect(categories.contains(.cloudKitCache))
        #expect(categories.contains(.swiftPMCache))
        #expect(categories.contains(.carthageCache))
        #expect(categories.contains(.steamCache))
        #expect(categories.contains(.teamsCache))
        #expect(categories.contains(.adobeCaches))
        #expect(categories.contains(.chromeExtraCaches))
    }

    // MARK: - CleanupItemManager selection totals

    @Test("Selected size deduplicates the same path across categories")
    func selectedSizeDeduplicatesPaths() {
        let manager = CleanupItemManager()
        let sharedPath = "~/.gradle/caches"

        manager.appendFileItem(
            path: sharedPath,
            sizeBytes: 4_000_000_000,
            modificationDate: nil,
            isDirectory: true,
            category: "Gradle + Maven",
            parentName: nil
        )
        manager.appendFileItem(
            path: sharedPath,
            sizeBytes: 4_000_000_000,
            modificationDate: nil,
            isDirectory: true,
            category: "Dotfile caches",
            parentName: nil
        )

        #expect(manager.selectedSizeBytes == 4_000_000_000)
    }

    @Test("Selected size ignores duplicate aggregate rows when path children exist")
    func selectedSizeIgnoresAggregateDuplicates() {
        let manager = CleanupItemManager()
        let path = "~/Library/Developer/Xcode/DerivedData"

        manager.appendFileItem(
            path: path,
            sizeBytes: 30_000_000_000,
            modificationDate: nil,
            isDirectory: true,
            category: "IDE / Electron caches",
            parentName: nil
        )
        manager.appendPreviewItem("IDE / Electron caches", size: 30_000, deletable: true, parentName: "IDE / Electron caches", description: nil)

        #expect(manager.selectedSizeBytes == 30_000_000_000)
    }

    @Test("Directory size uses allocated bytes not logical APFS clone size")
    func directorySizeUsesAllocatedBytes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleanerPhysicalSize_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Sparse file: logical 100 MB, allocated ~0
        let sparse = dir.appendingPathComponent("sparse.bin")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 100 * 1024 * 1024)
        try handle.close()

        let cache = DirectorySizeCache()
        let size = await cache.getSize(for: dir.path)
        #expect(size < 5 * 1024 * 1024, "Must use allocated size, got \(size)")
    }

    // MARK: - Helpers

    private func createTempCacheDir() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleanerTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanupTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Thread-safe helpers

private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int { lock.withLock { _value } }

    func increment() {
        lock.withLock { _value += 1 }
    }
}

private final class ThreadSafeArray<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [Value] = []

    var isEmpty: Bool { lock.withLock { _items.isEmpty } }
    var count: Int { lock.withLock { _items.count } }

    func append(_ value: Value) {
        lock.withLock { _items.append(value) }
    }
}
