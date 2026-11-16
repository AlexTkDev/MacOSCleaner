import Foundation
import OSLog
import CoreServices

private extension Logger {
    static let engine = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "CleanupEngine")
}

// MARK: - Timeout Configuration

/// Timeout configuration for different types of cleanup operations.
public struct CleanupTimeouts: Sendable {
    /// Fast operations (file/folder removal via FileManager)
    public var fast: Duration
    /// System commands (brew cleanup, npm cache clean, docker prune)
    public var system: Duration
    /// Full cycle operations (Xcode DerivedData, Simulator cleanup)
    public var full: Duration
    /// Scattered junk scanning (deep home directory scan)
    public var scatteredJunk: Duration

    public init(
        fast: Duration = .seconds(30),
        system: Duration = .seconds(120),
        full: Duration = .seconds(300),
        scatteredJunk: Duration = .seconds(600)
    ) {
        self.fast = fast
        self.system = system
        self.full = full
        self.scatteredJunk = scatteredJunk
    }

    public func timeout(for category: CleanupCategory) -> Duration {
        switch category {
        case .packageManagers, .docker, .languageCaches, .androidSDK, .timeMachineSnapshots, .userLogs, .messagingMedia:
            return system
        case .xcode, .iosSimulators, .appCaches, .ideCaches, .flutterDart, .systemCaches, .androidCaches, .gradleMaven, .dotfileCaches, .browserCaches, .chromeExtraCaches, .steamCache, .teamsCache, .adobeCaches, .cloudKitCache, .swiftPMCache, .carthageCache, .photosCache:
            return full
        case .scatteredJunk:
            return scatteredJunk
        case .appContainers, .dynamicCacheDiscovery, .largeFiles:
            return full
        default:
            return fast
        }
    }

    public static let `default` = CleanupTimeouts()
}

// MARK: - Engine Events

/// Events emitted by CleanupEngine for UI.
public enum CleanupEngineEvent: Sendable {
    case step(current: Int, total: Int, title: String)
    case result(label: String, freedMB: Int)
    case categoryResult(category: String, label: String, freedMB: Int)
    case preview(label: String, sizeMB: Int, deletable: Bool, parent: String?, description: String?)
    case log(String)
    case fileItem(path: String, sizeBytes: Int64, modificationDate: Date?, isDirectory: Bool, category: String, parentName: String?, isSelected: Bool = true, isCommandBacked: Bool = false, description: String? = nil)
}

// MARK: - Cleanup Result

/// Cleanup operation result.
public struct CleanupEngineResult: Sendable {
    public let label: String
    public let freedMB: Int
    public let freedBytes: Int64
    public let removedCount: Int
    public let skippedCount: Int
    public let failedCount: Int
    public let category: CleanupCategory?

    /// True when at least one path failed — must not be treated as full success.
    public var isPartialFailure: Bool { failedCount > 0 }
    public var isSuccess: Bool { failedCount == 0 }

    public init(
        label: String,
        freedMB: Int,
        freedBytes: Int64? = nil,
        removedCount: Int = 0,
        skippedCount: Int = 0,
        failedCount: Int = 0,
        category: CleanupCategory? = nil
    ) {
        self.label = label
        self.freedMB = freedMB
        self.freedBytes = freedBytes ?? Int64(freedMB * 1024 * 1024)
        self.removedCount = removedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.category = category
    }

    func withCategory(_ category: CleanupCategory) -> CleanupEngineResult {
        CleanupEngineResult(
            label: label,
            freedMB: freedMB,
            freedBytes: freedBytes,
            removedCount: removedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            category: category
        )
    }
}

// MARK: - Cleanup Categories

/// High-level categories available for cleanup.
public enum CleanupCategory: String, Sendable, CaseIterable, Identifiable {
    public var id: String { rawValue }

    case appCaches = "app_caches"
    case packageManagers = "package_managers"
    case browserCaches = "browser_caches"
    case messagingMedia = "messaging_media"
    case docker = "docker"
    case userLogs = "user_logs"
    case systemCaches = "system_caches"
    case appContainers = "app_containers"
    case dotfileCaches = "dotfile_caches"
    case scatteredJunk = "scattered_junk"
    case largeFiles = "large_files"
    case dynamicCacheDiscovery = "dynamic_cache_discovery"
    case timeMachineSnapshots = "time_machine_snapshots"

    // Phase 1 categories
    case gradleMaven = "gradle_maven"
    case flutterDart = "flutter_dart"
    case xcode = "xcode"
    case iosSimulators = "ios_simulators"
    case androidCaches = "android_caches"
    case androidSDK = "android_sdk"
    case ideCaches = "ide_caches"
    case languageCaches = "language_caches"

    // Phase 2: User data & system deep clean
    case iosBackups = "ios_backups"
    case mailDownloads = "mail_downloads"
    case savedAppState = "saved_app_state"
    case crashReporter = "crash_reporter"
    case assetsV2 = "assets_v2"
    case cloudKitCache = "cloudkit_cache"
    case swiftPMCache = "swiftpm_cache"
    case carthageCache = "carthage_cache"
    case steamCache = "steam_cache"
    case teamsCache = "teams_cache"
    case adobeCaches = "adobe_caches"
    case chromeExtraCaches = "chrome_extra_caches"
    case sharedFileLists = "shared_file_lists"

    // Phase 3: New categories from cleanup.json
    case photosCache = "photos_cache"
    case garminFitbit = "garmin_fitbit"
    case oldBackups = "old_backups"
    case aiModels = "ai_models"
    case installerPackages = "installer_packages"
    case dnsFlush = "dns_flush"
    case fontCache = "font_cache"
    case projectBuildArtifacts = "project_build_artifacts"
}

// MARK: - CleanupEngine Actor

/// Cleanup engine implementing a hybrid architecture:
/// - FileManager for safe file operations (caches, logs)
/// - Process for system commands (brew, npm, docker)
///
/// Supports:
/// - Configurable timeouts (30s/120s/300s)
/// - Graceful cancellation via Task
/// - Safety checks via SafetyManager
public actor CleanupEngine {
    private let commandRunner: any CommandRunning
    private let safetyManager: SafetyManager
    private let timeouts: CleanupTimeouts
    private let fileSystemContext: FileSystemContext
    private let fm = FileManager.default
    let fileActor: FileCleanupActor
    let processActor: ProcessCleanupActor
    let sizeCache: DirectorySizeCache

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        safetyManager: SafetyManager? = nil,
        timeouts: CleanupTimeouts = .default,
        fileSystemContext: FileSystemContext = .production
    ) {
        self.commandRunner = commandRunner
        self.fileSystemContext = fileSystemContext
        let safety = safetyManager ?? SafetyManager(
            homeDirectory: fileSystemContext.homePath,
            fileSystemContext: fileSystemContext
        )
        self.safetyManager = safety
        self.timeouts = timeouts
        let sharedSizeCache = DirectorySizeCache()
        self.sizeCache = sharedSizeCache
        self.fileActor = FileCleanupActor(
            safetyManager: safety,
            sizeCache: sharedSizeCache,
            fileSystemContext: fileSystemContext
        )
        self.processActor = ProcessCleanupActor(commandRunner: commandRunner)
    }

    // MARK: - Public Interface

    /// Runs cleanup for the specified categories with parallel execution.
    public func run(
        categories: [CleanupCategory],
        dryRun: Bool = false,
        options: CleanupOptions = CleanupOptions(),
        progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil
    ) async throws -> [CleanupEngineResult] {
        var results: [CleanupEngineResult] = []
        let total = categories.count

        let maxConcurrency = dryRun ? min(4, max(1, ProcessInfo.processInfo.activeProcessorCount)) : 1

        var pending = Array(categories.enumerated())
        var completedCount = 0

        return await CleanupEngine.$currentSelectedPaths.withValue(options.selectedPaths) {
            await CleanupEngine.$currentBypassTrash.withValue(options.bypassTrash) {
            await CleanupEngine.$currentPlannedCategories.withValue(Set(categories)) {
            await withTaskGroup(of: (Int, String, [CleanupEngineResult]).self) { group in

                for (index, category) in pending.prefix(maxConcurrency) {
                let title = Self.titleForCategory(category)
                group.addTask {
                    let wrappedProgress: (@Sendable (CleanupEngineEvent) -> Void)? = { event in
                        if case .result(let label, let freedMB) = event {
                            progress?(.categoryResult(category: title, label: label, freedMB: freedMB))
                        } else {
                            progress?(event)
                        }
                    }
                    let results = await self.runCategoryWithTimeout(
                        category,
                        dryRun: dryRun,
                        options: options,
                        progress: wrappedProgress
                    )
                    return (index, title, results)
                }
            }
            pending.removeFirst(min(maxConcurrency, pending.count))

            for await (_, title, categoryResults) in group {
                completedCount += 1
                progress?(.step(current: completedCount, total: total, title: title))
                results.append(contentsOf: categoryResults)

                if let next = pending.first {
                    let nextCategory = next.element
                    let nextTitle = Self.titleForCategory(nextCategory)
                    group.addTask {
                        let wrappedProgress: (@Sendable (CleanupEngineEvent) -> Void)? = { event in
                            if case .result(let label, let freedMB) = event {
                                progress?(.categoryResult(category: nextTitle, label: label, freedMB: freedMB))
                            } else {
                                progress?(event)
                            }
                        }
                        let results = await self.runCategoryWithTimeout(
                            nextCategory,
                            dryRun: dryRun,
                            options: options,
                            progress: wrappedProgress
                        )
                        return (next.offset, nextTitle, results)
                    }
                    pending.removeFirst()
                }
            }
        }

        return results
            }
            }
        }
    }

    private func runCategoryWithTimeout(
        _ category: CleanupCategory,
        dryRun: Bool,
        options: CleanupOptions,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?
    ) async -> [CleanupEngineResult] {
        let timeout = timeouts.timeout(for: category)
        let title = Self.titleForCategory(category)
        do {
            let results = try await withTimeout(timeout) {
                try await self.runCategory(category, dryRun: dryRun, options: options, progress: progress)
            }
            return results.map { $0.category == nil ? $0.withCategory(category) : $0 }
        } catch is CancellationError {
            progress?(.log("⚠️ \(title) — cancelled"))
            return []
        } catch {
            let isTimeout = (error as? CleanupEngineError) == .timeout
            let reason = isTimeout ? "timed out after \(Int(timeout.components.seconds))s" : error.localizedDescription
            progress?(.log("⚠️ \(title) — \(reason), skipped"))
            Logger.engine.warning("Category \(title) failed: \(reason)")
            return [CleanupEngineResult(
                label: title,
                freedMB: 0,
                freedBytes: 0,
                removedCount: 0,
                skippedCount: 1,
                failedCount: 1,
                category: category
            )]
        }
    }

    private func runCategory(
        _ category: CleanupCategory,
        dryRun: Bool,
        options: CleanupOptions,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?
    ) async throws -> [CleanupEngineResult] {
        switch category {
        case .appCaches: return try await cleanAppCaches(dryRun: dryRun, progress: progress)
        case .packageManagers: return try await cleanPackageManagers(dryRun: dryRun, progress: progress)
        case .gradleMaven: return try await cleanGradleMaven(dryRun: dryRun, progress: progress, cleanMaven: options.cleanMaven)
        case .flutterDart: return try await cleanFlutterDart(dryRun: dryRun, progress: progress)
        case .xcode: return try await cleanXcode(dryRun: dryRun, progress: progress, archiveOlderThanDays: options.xcodeArchivesOlderThanDays)
        case .iosSimulators: return try await cleanIOSSimulators(dryRun: dryRun, progress: progress)
        case .androidCaches: return try await cleanAndroidCaches(dryRun: dryRun, progress: progress)
        case .androidSDK: return try await cleanAndroidSDK(dryRun: dryRun, progress: progress)
        case .ideCaches: return try await cleanIDECaches(dryRun: dryRun, progress: progress)
        case .browserCaches: return try await cleanBrowserCaches(dryRun: dryRun, progress: progress)
        case .messagingMedia: return try await cleanMessagingMedia(dryRun: dryRun, progress: progress)
        case .docker: return try await cleanDocker(dryRun: dryRun, progress: progress)
        case .languageCaches: return try await cleanLanguageCaches(dryRun: dryRun, progress: progress, cleanModCache: options.cleanModCache)
        case .userLogs: return try await cleanUserLogs(dryRun: dryRun, progress: progress)
        case .systemCaches: return try await cleanSystemCaches(dryRun: dryRun, progress: progress)
        case .appContainers: return try await cleanAppContainers(dryRun: dryRun, progress: progress)
        case .dotfileCaches: return try await cleanDotfileCaches(dryRun: dryRun, progress: progress)
        case .scatteredJunk: return try await cleanScatteredJunk(dryRun: dryRun, cleanDSStore: options.cleanDSStore, progress: progress)
        case .largeFiles: return try await cleanLargeFiles(dryRun: dryRun, progress: progress)
        case .dynamicCacheDiscovery: return try await cleanDynamicCacheDiscovery(dryRun: dryRun, progress: progress)
        case .timeMachineSnapshots: return try await cleanTimeMachineSnapshots(dryRun: dryRun, progress: progress)
        case .iosBackups: return try await cleanIOSBackups(dryRun: dryRun, progress: progress)
        case .mailDownloads: return try await cleanMailDownloads(dryRun: dryRun, progress: progress)
        case .savedAppState: return try await cleanSavedAppState(dryRun: dryRun, progress: progress)
        case .crashReporter: return try await cleanCrashReporter(dryRun: dryRun, progress: progress)
        case .assetsV2: return try await cleanAssetsV2(dryRun: dryRun, progress: progress)
        case .cloudKitCache: return try await cleanCloudKitCache(dryRun: dryRun, progress: progress)
        case .swiftPMCache: return try await cleanSwiftPMCache(dryRun: dryRun, progress: progress)
        case .carthageCache: return try await cleanCarthageCache(dryRun: dryRun, progress: progress)
        case .steamCache: return try await cleanSteamCache(dryRun: dryRun, progress: progress)
        case .teamsCache: return try await cleanTeamsCache(dryRun: dryRun, progress: progress)
        case .adobeCaches: return try await cleanAdobeCaches(dryRun: dryRun, progress: progress)
        case .chromeExtraCaches: return try await cleanChromeExtraCaches(dryRun: dryRun, progress: progress)
        case .sharedFileLists: return try await cleanSharedFileLists(dryRun: dryRun, progress: progress)
        case .photosCache: return try await cleanPhotosCache(dryRun: dryRun, progress: progress)
        case .garminFitbit: return try await cleanGarminFitbit(dryRun: dryRun, progress: progress)
        case .oldBackups: return try await cleanOldBackups(dryRun: dryRun, progress: progress)
        case .aiModels: return try await cleanAIModels(dryRun: dryRun, progress: progress)
        case .installerPackages: return try await cleanInstallerPackages(dryRun: dryRun, progress: progress)
        case .dnsFlush: return try await cleanDNSFlush(dryRun: dryRun, progress: progress)
        case .fontCache: return try await cleanFontCache(dryRun: dryRun, progress: progress)
        case .projectBuildArtifacts: return try await cleanProjectBuildArtifacts(dryRun: dryRun, progress: progress, olderThanDays: options.projectArtifactsOlderThanDays)
        }
    }

    // MARK: - Heavy Container Skip List

    /// Bundle IDs of apps with very large container directories (virtual disks, images).
    /// These are skipped during size calculation and orphan scanning to avoid timeouts.
    static let heavyContainerBundleIDs: Set<String> = [
        "com.docker.docker",
        "dev.orbstack.OrbStack",
        "com.vmware.fusion",
        "com.parallels.desktop.console",
        "com.utmapp.UTM",
        "org.virtualbox.app.VirtualBox",
        "com.microsoft.rdc.macos",  // Remote Desktop — can have large caches
    ]

    /// Returns true if this container entry should be skipped due to known heavy content.
    private static func isHeavyContainer(_ entry: String) -> Bool {
        heavyContainerBundleIDs.contains(entry)
    }

    /// Scans the specified categories without deletion.
    public func scan(
        categories: [CleanupCategory],
        options: CleanupOptions = CleanupOptions(),
        progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil
    ) async throws -> [CleanupEngineResult] {
        return try await run(categories: categories, dryRun: true, options: options, progress: progress)
    }

    // MARK: - Timeout Wrapper

    private nonisolated func withTimeout<T: Sendable>(_ duration: Duration, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(for: duration)
                    throw CleanupEngineError.timeout
                }
                guard let result = try await group.next() else {
                    throw CleanupEngineError.timeout
                }
                group.cancelAll()
                return result
            }
        } onCancel: {
            // timeout task will be cancelled automatically
        }
    }

    // MARK: - Size Calculation with Timeout

    /// Calculates directory size with a timeout. Returns 0 if the calculation takes too long.
    func getDirectorySizeWithTimeout(_ path: String, timeout: Duration = .seconds(10)) async -> Int64 {
        do {
            return try await withTimeout(timeout) {
                await self.getDirectorySize(path)
            }
        } catch {
            Logger.engine.warning("Size calculation timed out for \(path, privacy: .public)")
            return 0
        }
    }

    // MARK: - Category Titles

    private static func titleForCategory(_ category: CleanupCategory) -> String {
        category.localizedTitle
    }
}

// MARK: - Cleanup Options

/// Options controlling which categories are cleaned.
public struct CleanupOptions: Sendable, Equatable {
    public static let `default` = CleanupOptions()

    public var targetCategories: [CleanupCategory]? = nil
    /// explicitly selected paths (or pseudo-paths) to clean. nil = clean everything.
    public var selectedPaths: Set<String>? = nil
    /// When true, includes .DS_Store and other scattered junk files.
    public var cleanDSStore: Bool = false
    /// When true, cleans Maven local repository (~/.m2/repository).
    public var cleanMaven: Bool = true
    /// When true, cleans Go module cache (GOMODCACHE).
    public var cleanModCache: Bool = true
    /// When true, cleans project-local build artifacts. Default is false (review-only).
    public var cleanProjectArtifacts: Bool = false
    /// Project build artifacts older than this many days will be cleaned (default: 60).
    public var projectArtifactsOlderThanDays: Int = 60
    /// Xcode Archives older than this many days will be cleaned.
    public var xcodeArchivesOlderThanDays: Int = 90
    /// When true, cleans Time Machine local snapshots.
    public var cleanTimeMachineSnapshots: Bool = false
    /// When true, flushes DNS cache. Default is false (opt-in).
    public var cleanDNSFlush: Bool = false
    /// When true, clears font cache databases (atsutil). Default is false (requires restart/breaks rendering).
    public var cleanFontCache: Bool = false
    /// When true, bypasses Trash and permanently deletes cleaned files.
    public var bypassTrash: Bool = false

    public init(
        targetCategories: [CleanupCategory]? = nil,
        selectedPaths: Set<String>? = nil,
        cleanDSStore: Bool = false,
        cleanMaven: Bool = true,
        cleanModCache: Bool = true,
        cleanProjectArtifacts: Bool = false,
        projectArtifactsOlderThanDays: Int = 60,
        xcodeArchivesOlderThanDays: Int = 90,
        cleanTimeMachineSnapshots: Bool = false,
        cleanDNSFlush: Bool = false,
        cleanFontCache: Bool = false,
        bypassTrash: Bool = false
    ) {
        self.targetCategories = targetCategories
        self.selectedPaths = selectedPaths
        self.cleanDSStore = cleanDSStore
        self.cleanMaven = cleanMaven
        self.cleanModCache = cleanModCache
        self.cleanProjectArtifacts = cleanProjectArtifacts
        self.projectArtifactsOlderThanDays = projectArtifactsOlderThanDays
        self.xcodeArchivesOlderThanDays = xcodeArchivesOlderThanDays
        self.cleanTimeMachineSnapshots = cleanTimeMachineSnapshots
        self.cleanDNSFlush = cleanDNSFlush
        self.cleanFontCache = cleanFontCache
        self.bypassTrash = bypassTrash
    }

    /// Categories the preview can offer: runnable cleanup plus review-only leaves.
    public func scanCategories() -> [CleanupCategory] {
        if let targetCategories {
            return targetCategories
        }
        var seen = Set<CleanupCategory>()
        var result: [CleanupCategory] = []
        for category in categories() + CleanupCategory.reviewOnly {
            if seen.insert(category).inserted {
                result.append(category)
            }
        }
        return result
    }

    /// Returns the set of categories to actually clean based on these options.
    ///
    /// Dangerous categories are excluded from automatic cleanup until they have
    /// per-item ownership proofs and explicit user selection:
    /// old backups, iOS backups, AI/LLM user_content, installer packages,
    /// large-file review items, project build artifacts.
    public func categories() -> [CleanupCategory] {
        if let targetCategories {
            return targetCategories
        }
        var categories: [CleanupCategory] = [
            .appCaches,
            .packageManagers,
            .browserCaches,
            .messagingMedia,
            .docker,
            .userLogs,
            .systemCaches,
            .appContainers,
            .dotfileCaches,
            .iosSimulators,
            .gradleMaven,
            .flutterDart,
            .xcode,
            .androidCaches,
            .androidSDK,
            .ideCaches,
            .languageCaches,
            .largeFiles,
            .dynamicCacheDiscovery,
            .mailDownloads,
            .savedAppState,
            .crashReporter,
            .assetsV2,
            .cloudKitCache,
            .swiftPMCache,
            .carthageCache,
            .steamCache,
            .teamsCache,
            .adobeCaches,
            .chromeExtraCaches,
            .sharedFileLists,
            .photosCache,
            .garminFitbit,
        ]

        if cleanDSStore {
            categories.append(.scatteredJunk)
        }
        if cleanDNSFlush {
            categories.append(.dnsFlush)
        }
        if cleanFontCache {
            categories.append(.fontCache)
        }
        if cleanProjectArtifacts {
            categories.append(.projectBuildArtifacts)
        }
        if cleanTimeMachineSnapshots {
            categories.append(.timeMachineSnapshots)
        }

        return categories
    }
}

// MARK: - CleanupEngineError

public enum CleanupEngineError: Error, LocalizedError, Equatable {
    case timeout
    case safetyViolation(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .timeout: return "error_timeout".localized
        case .safetyViolation(let path): return String(format: "error_safety_violation_format".localized, path)
        case .commandFailed(let msg): return String(format: "error_command_failed_format".localized, msg)
        }
    }

    public static func == (lhs: CleanupEngineError, rhs: CleanupEngineError) -> Bool {
        switch (lhs, rhs) {
        case (.timeout, .timeout): return true
        case (.safetyViolation(let a), .safetyViolation(let b)): return a == b
        case (.commandFailed(let a), .commandFailed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Logging Helpers

extension CleanupEngine {

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return String(format: "format_bytes_b".localized, bytes) }
        if bytes < 1024 * 1024 { return String(format: "format_bytes_kb".localized, Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "format_bytes_mb".localized, Double(bytes) / (1024 * 1024)) }
        return String(format: "format_bytes_gb".localized, Double(bytes) / (1024 * 1024 * 1024))
    }

    func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: fileSystemContext.homePath, with: "~")
    }
}

// MARK: - Task Locals

extension CleanupEngine {
    @TaskLocal static var currentSelectedPaths: Set<String>? = nil
    @TaskLocal static var currentBypassTrash: Bool = false
    @TaskLocal static var currentPlannedCategories: Set<CleanupCategory> = []
}

// MARK: - FileManager Helpers

extension CleanupEngine {

    func emitFileItem(_ item: CleanupFileItem?, category: String, parentName: String?, isSelected: Bool = true, isCommandBacked: Bool = false, progress: (@Sendable (CleanupEngineEvent) -> Void)?) {
        guard let item else { return }
        progress?(.fileItem(
            path: item.path,
            sizeBytes: item.sizeBytes,
            modificationDate: item.modificationDate,
            isDirectory: item.isDirectory,
            category: category,
            parentName: parentName,
            isSelected: isSelected,
            isCommandBacked: isCommandBacked,
            description: item.description
        ))
    }

    /// True when a non-nil selection exists and this path was not checked in the preview.
    func skipsUnselected(_ path: String, dryRun: Bool) -> Bool {
        guard !dryRun, let selected = CleanupEngine.currentSelectedPaths else { return false }
        return !selected.contains(CleanupItemManager.selectionKey(path))
    }

    func resolvedToolPath(_ stdout: String?, fallback: String) -> String {
        let trimmed = stdout?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    func cleanContents(of path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        if skipsUnselected(path, dryRun: dryRun) {
            return (0, nil)
        }
        let (freed, item, _) = try await fileActor.cleanContents(of: path, dryRun: dryRun, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
        return (freed, item)
    }

    func removeDirectory(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        if skipsUnselected(path, dryRun: dryRun) {
            return (0, nil)
        }
        return try await fileActor.removeDirectory(path, dryRun: dryRun, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
    }

    func removeFile(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        if skipsUnselected(path, dryRun: dryRun) {
            return (0, nil)
        }
        return try await fileActor.removeFile(path, dryRun: dryRun, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
    }

    func getDirectorySize(_ path: String) async -> Int64 {
        await fileActor.getDirectorySize(path)
    }

    func cleanOldFiles(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        if skipsUnselected(path, dryRun: dryRun) {
            return (0, nil)
        }
        return try await fileActor.cleanOldFiles(in: path, olderThanDays: days, dryRun: dryRun, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
    }

    func cleanOldFilesRecursive(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        if skipsUnselected(path, dryRun: dryRun) {
            return (0, nil)
        }
        return try await fileActor.cleanOldFilesRecursive(in: path, olderThanDays: days, dryRun: dryRun, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
    }

    func cleanContentsBatch(_ paths: [String], dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> Int64 {
        let pathsToClean = paths.filter { !skipsUnselected($0, dryRun: dryRun) }
        guard !pathsToClean.isEmpty else { return 0 }
        return try await fileActor.cleanContentsBatch(pathsToClean, dryRun: dryRun, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
    }

    /// Absolute existing paths from EmbeddedCleanupPaths (+ GeneratedCleanupPaths merge).
    func resolvedEmbeddedPaths(for category: CleanupCategory) -> [String] {
        resolvedEmbeddedEntries(for: category).map(\.path)
    }

    private func resolvedEmbeddedEntries(for category: CleanupCategory) -> [(path: String, descriptionKey: String?)] {
        let home = fileSystemContext.homePath
        var result: [(path: String, descriptionKey: String?)] = []
        var seen = Set<String>()
        for entry in EmbeddedCleanupPaths.paths(for: category) {
            for path in CleanupPathExpander.expand(entry.path, home: home, fileManager: fm) {
                if seen.insert(path).inserted {
                    result.append((path, entry.description))
                }
            }
        }
        return result
    }

    func resolveSubpaths(_ templates: [String]) -> [String] {
        let home = fileSystemContext.homePath
        return templates.map { $0.hasPrefix("~") ? home + $0.dropFirst() : $0 }
    }

    func cleanFromEmbeddedPaths(
        _ category: CleanupCategory,
        label: String,
        dryRun: Bool,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?
    ) async throws -> [CleanupEngineResult] {
        // EmbeddedCleanupPaths merges only GeneratedCleanupPaths.cachePaths —
        // shared / app_data / user_content never enter this executor.
        let entries = resolvedEmbeddedEntries(for: category).filter { !skipsUnselected($0.path, dryRun: dryRun) }
        progress?(.log("Scanning \(label) (\(entries.count) paths)..."))
        var totalFreed: Int64 = 0
        var removed = 0
        var skipped = 0
        var failed = 0
        for entry in entries {
            try Task.checkCancellation()
            do {
                let (freed, item, failedCount) = try await fileActor.cleanContents(of: entry.path, dryRun: dryRun, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
                if freed > 0 || item != nil {
                    removed += 1
                    totalFreed += freed
                } else if failedCount == 0 {
                    skipped += 1
                }
                failed += failedCount
                if dryRun, let item {
                    let described = entry.descriptionKey.map { key in
                        CleanupFileItem(
                            path: item.path,
                            sizeBytes: item.sizeBytes,
                            modificationDate: item.modificationDate,
                            isDirectory: item.isDirectory,
                            description: key.localized
                        )
                    } ?? item
                    emitFileItem(described, category: label, parentName: nil, progress: progress)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed += 1
                progress?(.log("  \(shortPath(entry.path)) — failed: \(error.localizedDescription)"))
            }
        }
        let mb = Int(totalFreed / (1024 * 1024))
        let countLabel = dryRun ? "found" : "removed"
        progress?(.log("\(label): \(countLabel)=\(removed) skipped=\(skipped) failed=\(failed) total=\(Self.formatBytes(totalFreed))"))
        if failed > 0 {
            progress?(.log("\(label): partial failure — not marking full success"))
        }
        progress?(.result(label: label, freedMB: mb))
        return [CleanupEngineResult(
            label: label,
            freedMB: mb,
            freedBytes: totalFreed,
            removedCount: removed,
            skippedCount: skipped,
            failedCount: failed
        )]
    }

    func withUserPath(_ command: String) async -> String {
        await processActor.withUserPath(command)
    }

    func commandExists(_ command: String) async -> Bool {
        await processActor.commandExists(command)
    }
}

// MARK: - Category Implementations: FileManager-Based

extension CleanupEngine {

    // MARK: 1. App Caches

    func cleanAppCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Only purpose:cache paths from the generated registry — never shared updaters / Keystone.
        var results = try await cleanFromEmbeddedPaths(.appCaches, label: "App caches", dryRun: dryRun, progress: progress)
        let sparkle = try await cleanSparkleUpdateDownloads(dryRun: dryRun, progress: progress)
        results.append(contentsOf: sparkle)
        return results
    }

    /// Stale Sparkle / Electron updater downloads under ~/Library/Caches — regenerable, safe.
    func cleanSparkleUpdateDownloads(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        let cachesDir = "\(home)/Library/Caches"
        let label = "Stale app updates"
        progress?(.log("Scanning Sparkle / updater download leftovers..."))
        var totalFreed: Int64 = 0
        var removed = 0
        var skipped = 0

        guard fm.fileExists(atPath: cachesDir) else {
            return [CleanupEngineResult(label: label, freedMB: 0)]
        }

        let entries = (try? fm.contentsOfDirectory(atPath: cachesDir)) ?? []
        for entry in entries {
            try Task.checkCancellation()
            if Self.isHeavyContainer(entry) { continue }
            let sparkleRoots = [
                "\(cachesDir)/\(entry)/org.sparkle-project.Sparkle/PersistentDownloads",
                "\(cachesDir)/\(entry)/org.sparkle-project.Sparkle/Installation",
                "\(cachesDir)/\(entry)/Squirrel",
            ]
            for path in sparkleRoots {
                guard fm.fileExists(atPath: path) else { continue }
                let (freed, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
                if freed > 0 || item != nil {
                    removed += 1
                    totalFreed += freed
                    if dryRun {
                        emitFileItem(item, category: "App caches", parentName: label, progress: progress)
                    }
                } else {
                    skipped += 1
                }
            }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("\(label): \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: label, freedMB: mb))
        return [CleanupEngineResult(
            label: label,
            freedMB: mb,
            freedBytes: totalFreed,
            removedCount: removed,
            skippedCount: skipped,
            failedCount: 0
        )]
    }

    // MARK: 2. Package Managers (FileManager + Process)

    func cleanPackageManagers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        var results: [CleanupEngineResult] = []
        let home = fileSystemContext.homePath
        progress?(.log("Checking package managers..."))

        // Homebrew
        if await commandRunner.commandExists("brew") {
            progress?(.log("  Homebrew detected"))
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("brew --cache 2>/dev/null")]).stdout
            let cacheDir = resolvedToolPath(cachePath, fallback: "\(home)/Library/Caches/Homebrew")
            progress?(.log("  Cache path: \(shortPath(cacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  Homebrew cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "Homebrew cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                if skipsUnselected(cacheDir, dryRun: dryRun) {
                    progress?(.log("  skipped (not selected)"))
                    results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: 0, skippedCount: 1))
                } else {
                    let before = await getDirectorySize(cacheDir)
                    progress?(.log("  Running: brew cleanup --prune=all -q"))
                    _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("brew cleanup --prune=all -q")], timeout: timeouts.system)
                    let after = await getDirectorySize(cacheDir)
                    let freed = Int(max(0, before - after) / (1024 * 1024))
                    progress?(.log("  Homebrew: freed \(Self.formatBytes(max(0, before - after)))"))
                    progress?(.result(label: "Homebrew cache", freedMB: freed))
                    results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: freed))
                }
            }
        } else {
            progress?(.log("  Homebrew not found, skipped"))
        }

        // npm
        if await commandRunner.commandExists("npm") {
            progress?(.log("  npm detected"))
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("npm config get cache 2>/dev/null")], timeout: timeouts.fast).stdout
            let cacheDir = resolvedToolPath(cachePath, fallback: "\(home)/.npm")
            progress?(.log("  Cache path: \(shortPath(cacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  npm cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "npm cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else if skipsUnselected(cacheDir, dryRun: dryRun) {
                progress?(.log("  skipped (not selected)"))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: 0, skippedCount: 1))
            } else {
                let before = await getDirectorySize(cacheDir)
                progress?(.log("  Running: npm cache clean --force"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("npm cache clean --force 2>/dev/null")], timeout: timeouts.system)
                let after = await getDirectorySize(cacheDir)
                var freed = Int(max(0, before - after) / (1024 * 1024))
                // Fallback: manual cleanup via FileCleanupActor if npm didn't free space
                if freed == 0 && before > 0 {
                    progress?(.log("  npm cache clean didn't free space, trying manual cleanup..."))
                    let cacheURL = URL(fileURLWithPath: cacheDir)
                    if (try? safetyManager.validate(url: cacheURL)) != nil {
                        let (cleanedFreed, _) = try await cleanContents(of: cacheDir, dryRun: false, progress: progress)
                        freed = Int(cleanedFreed / (1024 * 1024))
                    } else {
                        progress?(.log("  npm cache path failed safety validation, skipping manual cleanup"))
                    }
                }
                progress?(.log("  npm: freed \(Self.formatBytes(max(0, before - after)))"))
                progress?(.result(label: "npm cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: freed))
            }
        } else {
            progress?(.log("  npm not found, skipped"))
        }

        // yarn (v1 vs v2+ Berry)
        if await commandRunner.commandExists("yarn") {
            progress?(.log("  yarn detected"))
            let versionOut = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("yarn --version 2>/dev/null")]).stdout
            let trimmedVer = versionOut?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isBerry = !trimmedVer.isEmpty && !trimmedVer.hasPrefix("1.")
            let cachePath = isBerry
                ? nil
                : (try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("yarn cache dir 2>/dev/null")]).stdout)
            let defaultYarnCache = isBerry ? "\(home)/.yarn/berry/cache" : "\(home)/Library/Caches/Yarn"
            let cacheDir = resolvedToolPath(cachePath, fallback: defaultYarnCache)
            let cleanCmd = isBerry ? "yarn cache clean --all 2>/dev/null" : "yarn cache clean 2>/dev/null"
            progress?(.log("  Cache path: \(shortPath(cacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  yarn cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "yarn cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "yarn cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                if skipsUnselected(cacheDir, dryRun: dryRun) {
                    progress?(.log("  skipped (not selected)"))
                    results.append(CleanupEngineResult(label: "yarn cache", freedMB: 0, skippedCount: 1))
                } else {
                    let before = await getDirectorySize(cacheDir)
                    progress?(.log("  Running: \(isBerry ? "yarn cache clean --all" : "yarn cache clean")"))
                    _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath(cleanCmd)])
                    let after = await getDirectorySize(cacheDir)
                    let freed = Int(max(0, before - after) / (1024 * 1024))
                    progress?(.log("  yarn: freed \(Self.formatBytes(max(0, before - after)))"))
                    progress?(.result(label: "yarn cache", freedMB: freed))
                    results.append(CleanupEngineResult(label: "yarn cache", freedMB: freed))
                }
            }
        } else {
            progress?(.log("  yarn not found, skipped"))
        }

        // pnpm
        if await commandRunner.commandExists("pnpm") {
            progress?(.log("  pnpm detected"))
            let storePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("pnpm store path 2>/dev/null")]).stdout
            let storeDir = resolvedToolPath(storePath, fallback: "\(home)/Library/pnpm/store")
            progress?(.log("  Store path: \(shortPath(storeDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(storeDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  pnpm store: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "pnpm store", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "pnpm store", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: storeDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                if skipsUnselected(storeDir, dryRun: dryRun) {
                    progress?(.log("  skipped (not selected)"))
                    results.append(CleanupEngineResult(label: "pnpm store", freedMB: 0, skippedCount: 1))
                } else {
                    let before = await getDirectorySize(storeDir)
                    progress?(.log("  Running: pnpm store prune"))
                    _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("pnpm store prune 2>/dev/null")])
                    let after = await getDirectorySize(storeDir)
                    let freed = Int(max(0, before - after) / (1024 * 1024))
                    progress?(.log("  pnpm: freed \(Self.formatBytes(max(0, before - after)))"))
                    progress?(.result(label: "pnpm store", freedMB: freed))
                    results.append(CleanupEngineResult(label: "pnpm store", freedMB: freed))
                }
            }
        } else {
            progress?(.log("  pnpm not found, skipped"))
        }

        // CocoaPods
        let cocoapodsCacheDir = "\(home)/Library/Caches/CocoaPods"
        if await commandExists("pod") {
            progress?(.log("  CocoaPods detected"))
            progress?(.log("  Cache path: \(shortPath(cocoapodsCacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cocoapodsCacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  CocoaPods cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "CocoaPods cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cocoapodsCacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                if skipsUnselected(cocoapodsCacheDir, dryRun: dryRun) {
                    progress?(.log("  skipped (not selected)"))
                    results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: 0, skippedCount: 1))
                } else {
                    let before = await getDirectorySize(cocoapodsCacheDir)
                    progress?(.log("  Running: pod cache clean --all"))
                    _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("pod cache clean --all 2>/dev/null")])
                    let after = await getDirectorySize(cocoapodsCacheDir)
                    let freed = Int(max(0, before - after) / (1024 * 1024))
                    progress?(.log("  CocoaPods: freed \(Self.formatBytes(max(0, before - after)))"))
                    progress?(.result(label: "CocoaPods cache", freedMB: freed))
                    results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: freed))
                }
            }
        } else if fm.fileExists(atPath: cocoapodsCacheDir) {
            let (freedBytes, item) = try await cleanContents(of: cocoapodsCacheDir, dryRun: dryRun, progress: progress)
            let mb = Int(freedBytes / (1024 * 1024))
            if dryRun { emitFileItem(item, category: "Package managers", parentName: nil, progress: progress) }
            progress?(.result(label: "CocoaPods cache", freedMB: mb))
            results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: mb))
        } else {
            progress?(.log("  CocoaPods not found, skipped"))
        }

        return results
    }

    // MARK: 3. Gradle + Maven

    func cleanGradleMaven(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?, cleanMaven: Bool = true) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Gradle + Maven caches..."))
        var freed: Int64 = 0

        let paths = resolveSubpaths(EmbeddedCleanupPaths.gradleCacheSubpaths)
        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Gradle + Maven", parentName: nil, progress: progress) }
        }

        // Maven — OPT-IN only
        let mavenPath = "\(home)/.m2/repository"
        if fm.fileExists(atPath: mavenPath) {
            if cleanMaven {
                let (f, item) = try await cleanContents(of: mavenPath, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Gradle + Maven", parentName: nil, progress: progress) }
            } else {
                let size = await getDirectorySize(mavenPath)
                progress?(.log("  Maven repo: \(Self.formatBytes(size)) — skipped (enable cleanMaven option to clean)"))
                if dryRun {
                    emitFileItem(CleanupFileItem(path: mavenPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Gradle + Maven", parentName: "Opt-in only", progress: progress)
                }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Gradle + Maven total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Gradle caches + wrapper + daemon", freedMB: mb))
        return [CleanupEngineResult(label: "Gradle + Maven", freedMB: mb)]
    }

    // MARK: 4. Flutter / Dart

    func cleanFlutterDart(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Scanning Flutter / Dart caches..."))
        var freed: Int64 = 0

        let dirs = resolveSubpaths(EmbeddedCleanupPaths.flutterDartCacheSubpaths)
        for path in dirs {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Flutter / Dart", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Flutter / Dart total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Dart/Flutter package caches", freedMB: mb))
        return [CleanupEngineResult(label: "Flutter / Dart", freedMB: mb)]
    }

    // MARK: 5. Xcode

    func cleanXcode(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?, archiveOlderThanDays: Int = 90) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Xcode caches..."))
        var freed: Int64 = 0

        let contentsPaths = [
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/watchOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/visionOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/DocumentationCache",
            "\(home)/Library/Developer/Xcode/UserData/IB Support",
            "\(home)/Library/Developer/Xcode/UserData/Previews/Simulator Devices",
            "\(home)/Library/Developer/Xcode/Products",
            "\(home)/Library/Developer/Xcode/clangd"
        ]
        for path in contentsPaths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Xcode", parentName: nil, progress: progress) }
        }
        let (af, ai) = try await cleanOldFiles(in: "\(home)/Library/Developer/Xcode/Archives", olderThanDays: archiveOlderThanDays, dryRun: dryRun, progress: progress)
        freed += af
        if dryRun { emitFileItem(ai, category: "Xcode", parentName: nil, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Xcode total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Xcode cleanup", freedMB: mb))
        return [CleanupEngineResult(label: "Xcode", freedMB: mb)]
    }

    // MARK: - Project Build Artifacts

    func cleanProjectBuildArtifacts(
        dryRun: Bool,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?,
        olderThanDays: Int = 60
    ) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning project build artifacts (older than \(olderThanDays) days)..."))
        let freed = try await cleanProjectLocalBuildArtifacts(
            home: home,
            dryRun: dryRun,
            progress: progress,
            olderThanDays: olderThanDays
        )
        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Project build artifacts total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Project build artifacts", freedMB: mb))
        return [CleanupEngineResult(label: "Project build artifacts", freedMB: mb)]
    }

    /// Scans common developer directories for project-local build artifacts.
    /// Filters by mtime of the artifact directory (older than olderThanDays).
    /// All targets are 100% regenerable by their respective build tools.
    private func cleanProjectLocalBuildArtifacts(
        home: String,
        dryRun: Bool,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?,
        olderThanDays: Int = 60
    ) async throws -> Int64 {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) ?? Date.distantPast
        let searchRoots = ProjectArtifactRules.searchRoots(home: home)
        let maxDepth = 5
        var freed: Int64 = 0
        var foundCount = 0

        progress?(.log("  Scanning project-local build artifacts..."))

        for root in searchRoots {
            guard fm.fileExists(atPath: root) else { continue }
            try Task.checkCancellation()

            let rootURL = URL(fileURLWithPath: root)
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            while let obj = enumerator.nextObject() {
                try Task.checkCancellation()
                guard let url = obj as? URL else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else { continue }

                let name = url.lastPathComponent
                let depth = url.pathComponents.count - rootURL.pathComponents.count

                if depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                if ProjectArtifactRules.skipDescentNames.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }

                guard ProjectArtifactRules.isArtifact(at: url, home: home, fileManager: fm) else {
                    continue
                }

                if let attrs = try? fm.attributesOfItem(atPath: url.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate > cutoffDate {
                    // Keep recently modified directories; for `.gradle`, still descend so
                    // an older `.gradle/build-cache` inside can be discovered.
                    if name != ".gradle" {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                enumerator.skipDescendants()
                do {
                    let (f, item) = try await removeDirectory(url.path, dryRun: dryRun, progress: progress)
                    freed += f
                    foundCount += 1
                    if dryRun {
                        emitFileItem(item, category: "Project build artifacts", parentName: "Project build artifacts", isSelected: false, progress: progress)
                    }
                } catch is SafetyError {
                    progress?(.log("  \(shortPath(url.path)) — protected, skipped"))
                }
            }
        }

        if foundCount > 0 {
            progress?(.log("  Project-local build artifacts: \(foundCount) directories, \(Self.formatBytes(freed))"))
        }
        return freed
    }

    // MARK: 6. iOS Simulators

    func cleanIOSSimulators(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning iOS simulator caches..."))
        var freed: Int64 = 0

        let (cf, ci) = try await cleanContents(of: "\(home)/Library/Developer/CoreSimulator/Caches", dryRun: dryRun, progress: progress)
        freed += cf
        if dryRun { emitFileItem(ci, category: "iOS Simulators", parentName: nil, isSelected: false, progress: progress) }

        if await commandRunner.commandExists("xcrun") {
            let deleteUnavailable = "command://simctl/delete-unavailable"
            let deleteRuntimes = "command://simctl/delete-old-runtimes"
            let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl list devices 2>/dev/null | grep -c 'unavailable' || echo 0"])
            let count = Int(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
            progress?(.log("  Unavailable simulator devices: \(count)"))
            if dryRun, count > 0 {
                emitFileItem(
                    CleanupFileItem(path: deleteUnavailable, sizeBytes: 0, modificationDate: nil, isDirectory: false),
                    category: "iOS Simulators",
                    parentName: nil,
                    isSelected: false,
                    isCommandBacked: true,
                    progress: progress
                )
            } else if !dryRun, count > 0, !skipsUnselected(deleteUnavailable, dryRun: dryRun) {
                progress?(.log("  Running: xcrun simctl delete unavailable"))
                let deleted = try? await commandRunner.run(command: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"])
                if deleted?.exitCode == 0 {
                    progress?(.log("  Deleted \(count) unavailable devices"))
                } else {
                    progress?(.log("  simctl delete unavailable failed"))
                }
            }

            let runtimesResult = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl list runtimes 2>/dev/null | grep '^iOS' | awk '{print $NF}' | sort -V"])
            if let output = runtimesResult?.stdout {
                let runtimeIDs = output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
                progress?(.log("  Found \(runtimeIDs.count) iOS runtimes"))

                if runtimeIDs.count > 1 {
                    let stableRuntimes = runtimeIDs.filter {
                        let lower = $0.lowercased()
                        return !lower.contains("rc") && !lower.contains("beta") && !lower.contains("alpha") && !lower.contains("preview")
                    }
                    let sortedStable = stableRuntimes.sorted { ($0 as NSString).compare($1, options: .numeric) == .orderedAscending }
                    if let keepRuntime = sortedStable.last ?? runtimeIDs.last {
                        if dryRun {
                            emitFileItem(
                                CleanupFileItem(path: deleteRuntimes, sizeBytes: 0, modificationDate: nil, isDirectory: false),
                                category: "iOS Simulators",
                                parentName: nil,
                                isSelected: false,
                                isCommandBacked: true,
                                progress: progress
                            )
                            progress?(.log("  ⊘ Would delete iOS runtimes other than \(keepRuntime)"))
                        } else if !skipsUnselected(deleteRuntimes, dryRun: dryRun) {
                            let cryptexPath = "\(home)/Library/Developer/CoreSimulator/Cryptex"
                            let beforeSize = await getDirectorySize(cryptexPath)
                            for runtime in runtimeIDs where runtime != keepRuntime {
                                progress?(.log("  Deleting iOS runtime: \(runtime)"))
                                let deleted = try? await commandRunner.run(
                                    command: "/bin/bash",
                                    arguments: ["-c", "xcrun simctl runtime delete \(ShellQuoting.shellQuoted(runtime)) 2>/dev/null"]
                                )
                                if deleted?.exitCode != 0 {
                                    progress?(.log("  Failed to delete runtime \(runtime)"))
                                }
                            }
                            let afterSize = await getDirectorySize(cryptexPath)
                            let rtFreed = max(0, beforeSize - afterSize)
                            freed += rtFreed
                            progress?(.log("  iOS runtimes freed: \(Self.formatBytes(rtFreed))"))
                        }
                    }
                } else if runtimeIDs.count == 1 {
                    progress?(.log("  Only one iOS runtime installed, nothing to remove"))
                }
            }
        }

        // Clean simulator app caches
        let devicesPath = "\(home)/Library/Developer/CoreSimulator/Devices"
        if fm.fileExists(atPath: devicesPath) {
            let allEntries = (try? fm.contentsOfDirectory(atPath: devicesPath)) ?? []
            // Filter out non-device entries (.DS_Store, device_set.plist, device_set.plist.sb-*)
            let devices = allEntries.filter { entry in
                guard !entry.hasPrefix("."), !entry.hasPrefix("device_set.plist"), entry.contains("-") else {
                    return false
                }
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: "\(devicesPath)/\(entry)", isDirectory: &isDir) && isDir.boolValue
            }
            let deviceCount = devices.count
            progress?(.log("  Found \(deviceCount) simulator devices"))
            for device in devices {
                let cachesPath = "\(devicesPath)/\(device)/data/Library/Caches"
                let tmpPath = "\(devicesPath)/\(device)/data/tmp"
                let (f1, i1) = try await cleanContents(of: cachesPath, dryRun: dryRun, progress: progress)
                freed += f1
                if dryRun { emitFileItem(i1, category: "iOS Simulators", parentName: nil, isSelected: false, progress: progress) }
                let (f2, i2) = try await cleanContents(of: tmpPath, dryRun: dryRun, progress: progress)
                freed += f2
                if dryRun { emitFileItem(i2, category: "iOS Simulators", parentName: nil, isSelected: false, progress: progress) }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("iOS simulators total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Simulator caches", freedMB: mb))
        return [CleanupEngineResult(label: "iOS Simulators", freedMB: mb)]
    }

    // MARK: 7. Android Caches

    func cleanAndroidCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Android caches..."))
        var freed: Int64 = 0

        let paths = resolveSubpaths(EmbeddedCleanupPaths.androidCacheSubpaths)
        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Android caches", parentName: nil, progress: progress) }
        }

        // Android Studio caches (dynamic discovery)
        let googleCachesPath = "\(home)/Library/Caches/Google"
        if fm.fileExists(atPath: googleCachesPath) {
            let asDirs = (try? fm.contentsOfDirectory(atPath: googleCachesPath))?.filter { $0.hasPrefix("AndroidStudio") } ?? []
            for dir in asDirs {
                let path = "\(googleCachesPath)/\(dir)"
                let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Android caches", parentName: "Android Studio: \(dir)", progress: progress) }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Android caches total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Android build caches", freedMB: mb))
        return [CleanupEngineResult(label: "Android caches", freedMB: mb)]
    }

    // MARK: 8. Android SDK

    func cleanAndroidSDK(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        let sdkPath = "\(home)/Library/Android/sdk"
        progress?(.log("Scanning Android SDK..."))

        var freed: Int64 = 0

        // Clean build-tools (keep latest stable)
        if fm.fileExists(atPath: "\(sdkPath)/build-tools") {
            let allVersions = (try? fm.contentsOfDirectory(atPath: "\(sdkPath)/build-tools")) ?? []
            // Filter out .DS_Store and non-version entries
            let versions = allVersions.filter { $0 != ".DS_Store" && $0.contains(".") }
            let stableVersions = versions.filter { !$0.lowercased().contains("rc") && !$0.lowercased().contains("alpha") && !$0.lowercased().contains("beta") && !$0.lowercased().contains("preview") }
            // Sort by version using NSString
            let sortedStable = stableVersions.sorted { v1, v2 in
                (v1 as NSString).compare(v2, options: .numeric) == .orderedAscending
            }
            let keepVersion = sortedStable.last
            let removeCount = versions.count - 1

            if let keepVersion {
                progress?(.log("  build-tools: keeping \(keepVersion), removing \(removeCount) older versions"))
            }

            for version in versions {
                guard version != keepVersion else { continue }
                let dir = "\(sdkPath)/build-tools/\(version)"
                let (f, item) = try await removeDirectory(dir, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Android SDK", parentName: nil, isSelected: false, progress: progress) }
            }
        }

        // Clean platforms (keep latest)
        if fm.fileExists(atPath: "\(sdkPath)/platforms") {
            let allVersions = (try? fm.contentsOfDirectory(atPath: "\(sdkPath)/platforms")) ?? []
            // Filter out .DS_Store
            let versions = allVersions.filter { $0 != ".DS_Store" && $0.hasPrefix("android-") }
            // Sort by version (android-35, android-36, android-36.1, etc.) using NSString
            let sortedVersions = versions.sorted { v1, v2 in
                (v1 as NSString).compare(v2, options: .numeric) == .orderedAscending
            }
            let keepVersion = sortedVersions.last
            let removeCount = versions.count - 1

            if let keepVersion {
                progress?(.log("  platforms: keeping \(keepVersion), removing \(removeCount) older versions"))
            }

            for version in versions {
                guard version != keepVersion else { continue }
                let dir = "\(sdkPath)/platforms/\(version)"
                let (f, item) = try await removeDirectory(dir, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Android SDK", parentName: nil, isSelected: false, progress: progress) }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Android SDK total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Android SDK cleanup", freedMB: mb))
        return [CleanupEngineResult(label: "Android SDK", freedMB: mb)]
    }

    // MARK: 9. IDE / Electron Caches

    func cleanIDECaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        let ideDirs = resolvedEmbeddedPaths(for: .ideCaches)

        // Known apps to skip in dynamic discovery
        let knownApps: Set<String> = [
            "Cursor", "Code", "Code - Insiders", "Windsurf", "Antigravity",
            "Claude", "ChatGPT", "Gemini", "Perplexity", "GitHub Desktop",
            "Slack", "discord", "Figma", "Notion", "Postman", "Insomnia", "Linear", "Atom",
            "ai.opencode.desktop", "Nova", "Sublime Text", "dev.zed.Zed"
        ]

        progress?(.log("Scanning IDE / Electron caches (\(ideDirs.count) paths)..."))
        var totalFreed: Int64 = 0
        for dir in ideDirs {
            try Task.checkCancellation()
            do {
                let (freed, item) = try await cleanContents(of: dir, dryRun: dryRun, progress: progress)
                totalFreed += freed
                if dryRun { emitFileItem(item, category: "IDE / Electron caches", parentName: nil, progress: progress) }
            } catch is SafetyError {
                progress?(.log("  \(shortPath(dir)) — protected, skipped"))
            }
        }

        // Dynamic discovery: unknown Electron apps — Cache / Code Cache / GPUCache / CachedData
        let electronLeaves = ["Cache", "Code Cache", "GPUCache", "CachedData"]
        let appSupportPath = "\(home)/Library/Application Support"
        if fm.fileExists(atPath: appSupportPath) {
            let apps = (try? fm.contentsOfDirectory(atPath: appSupportPath)) ?? []
            for appDir in apps {
                try Task.checkCancellation()
                guard !knownApps.contains(appDir), appDir != "Apple" else { continue }
                let appSupportSubdir = "\(appSupportPath)/\(appDir)"
                if safetyManager.isBrowserUserDataPath(appSupportSubdir) { continue }
                for leaf in electronLeaves {
                    let cachePath = "\(appSupportSubdir)/\(leaf)"
                    guard fm.fileExists(atPath: cachePath) else { continue }
                    let size = await getDirectorySize(cachePath)
                    guard size >= 5 * 1024 * 1024 else { continue } // skip < 5 MB
                    do {
                        let (freed, item) = try await cleanContents(of: cachePath, dryRun: dryRun, progress: progress)
                        totalFreed += freed
                        if dryRun {
                            emitFileItem(item, category: "IDE / Electron caches", parentName: "\(appDir)/\(leaf)", progress: progress)
                        }
                    } catch is SafetyError {
                        progress?(.log("  \(shortPath(cachePath)) — protected, skipped"))
                    }
                }
            }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("IDE / Electron total: \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: "IDE / Electron caches", freedMB: mb))
        return [CleanupEngineResult(label: "IDE / Electron caches", freedMB: mb)]
    }

    // MARK: 10. Browser Caches

    func cleanBrowserCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        return try await cleanFromEmbeddedPaths(.browserCaches, label: "Browser caches", dryRun: dryRun, progress: progress)
    }

    // MARK: 11. Messaging / Media

    func cleanMessagingMedia(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Never touch ~/Library/Messages/Attachments — those are user media, not regenerable cache.
        return try await cleanFromEmbeddedPaths(.messagingMedia, label: "Messaging / media", dryRun: dryRun, progress: progress)
    }

    // MARK: 12. Docker

    func cleanDocker(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Detect Docker environment: OrbStack, Docker Desktop, or standard Docker
        let dockerHost = await detectDockerHost()
        
        guard let dockerHost = dockerHost else {
            progress?(.log("Docker not found (checked OrbStack, Docker Desktop, standard), skipped"))
            return [CleanupEngineResult(label: "Docker", freedMB: 0)]
        }

        progress?(.log("Checking Docker disk usage (\(dockerHost))..."))
        let quotedHost = ShellQuoting.shellQuoted(dockerHost)
        let dfCommand = "docker -H \(quotedHost) system df --format '{{.Reclaimable}}' 2>/dev/null"
        let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", dfCommand])
        let output = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var totalReclaimableMB = 0
        let lines = output.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            progress?(.log("  Reclaimable: \(trimmed)"))
            if trimmed.hasSuffix("GB") {
                if let val = Double(trimmed.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                    totalReclaimableMB += Int(val * 1024)
                }
            } else if trimmed.hasSuffix("MB") {
                if let val = Double(trimmed.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                    totalReclaimableMB += Int(val)
                }
            } else if trimmed.hasSuffix("kB") || trimmed.hasSuffix("KB") {
                if let val = Double(trimmed.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                    totalReclaimableMB += Int(val / 1024)
                }
            }
        }

        let dockerRoot = dockerHost.hasPrefix("unix://") ? dockerHost.replacingOccurrences(of: "unix://", with: "") : "/var/lib/docker"

        if dryRun {
            if totalReclaimableMB > 0 {
                progress?(.log("  Total reclaimable: ~\(totalReclaimableMB) MB"))
                progress?(.result(label: "Docker reclaimable space", freedMB: totalReclaimableMB))
                emitFileItem(CleanupFileItem(path: dockerRoot, sizeBytes: Int64(totalReclaimableMB) * 1024 * 1024, modificationDate: nil, isDirectory: true), category: "Docker", parentName: nil, isSelected: false, progress: progress)
            } else {
                progress?(.log("  Nothing reclaimable"))
                progress?(.log("Docker: nothing reclaimable"))
            }
            return [CleanupEngineResult(label: "Docker", freedMB: totalReclaimableMB)]
        } else {
            if skipsUnselected(dockerRoot, dryRun: dryRun) {
                progress?(.log("  skipped (not selected)"))
                return [CleanupEngineResult(label: "Docker", freedMB: 0, skippedCount: 1)]
            }
            let pruneCommand = "docker -H \(quotedHost) system prune -af 2>/dev/null"
            progress?(.log("  Running: \(pruneCommand)"))
            let prune = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", pruneCommand])
            guard prune?.exitCode == 0 else {
                progress?(.log("  Docker prune failed"))
                return [CleanupEngineResult(label: "Docker", freedMB: 0, failedCount: 1)]
            }
            progress?(.log("  Docker: freed ~\(totalReclaimableMB) MB"))
            progress?(.result(label: "Docker cleanup", freedMB: totalReclaimableMB))
            return [CleanupEngineResult(label: "Docker", freedMB: totalReclaimableMB)]
        }
    }

    private func detectDockerHost() async -> String? {
        let home = fileSystemContext.homePath
        
        // Check OrbStack first (user confirmed OrbStack)
        let orbStackSocket = "\(home)/.orbstack/docker.sock"
        if fm.fileExists(atPath: orbStackSocket) {
            return "unix://\(orbStackSocket)"
        }
        
        // Check OrbStack alternative location
        let orbStackSocketAlt = "/var/run/docker.sock"
        if fm.fileExists(atPath: orbStackSocketAlt) {
            // Verify it's OrbStack by checking if OrbStack app exists
            if fm.fileExists(atPath: "/Applications/OrbStack.app") || fm.fileExists(atPath: "\(home)/Applications/OrbStack.app") {
                return "unix://\(orbStackSocketAlt)"
            }
        }
        
        // Check Docker Desktop
        let dockerDesktopSocket = "\(home)/Library/Containers/com.docker.docker/Data/docker.raw.sock"
        if fm.fileExists(atPath: dockerDesktopSocket) {
            return "unix://\(dockerDesktopSocket)"
        }
        
        let dockerDesktopSocketAlt = "\(home)/.docker/run/docker.sock"
        if fm.fileExists(atPath: dockerDesktopSocketAlt) {
            return "unix://\(dockerDesktopSocketAlt)"
        }
        
        // Fall back to standard Docker CLI (if in PATH)
        if await commandRunner.commandExists("docker") {
            // Test if docker CLI works without explicit host
            let testResult = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "docker version 2>/dev/null"])
            if testResult?.exitCode == 0 {
                return "" // Empty means use default docker CLI
            }
        }
        
        // Check Colima
        let colimaSocket = "\(home)/.colima/default/docker.sock"
        if fm.fileExists(atPath: colimaSocket) {
            return "unix://\(colimaSocket)"
        }
        
        return nil
    }

    // MARK: 13. Language Caches

    func cleanLanguageCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?, cleanModCache: Bool = true) async throws -> [CleanupEngineResult] {
        var results = try await cleanFromEmbeddedPaths(.languageCaches, label: "Language caches", dryRun: dryRun, progress: progress)
        let home = fileSystemContext.homePath
        var extraFreedBytes: Int64 = 0

        if await commandRunner.commandExists("go") {
            let goCacheOut = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go env GOCACHE 2>/dev/null")]).stdout
            let goCacheDir = resolvedToolPath(goCacheOut, fallback: "\(home)/Library/Caches/go-build")
            if fm.fileExists(atPath: goCacheDir) {
                if dryRun {
                    let size = await getDirectorySize(goCacheDir)
                    extraFreedBytes += size
                    emitFileItem(CleanupFileItem(path: goCacheDir, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Language caches", parentName: "Go Build Cache", progress: progress)
                } else if !skipsUnselected(goCacheDir, dryRun: dryRun) {
                    let before = await getDirectorySize(goCacheDir)
                    _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go clean -cache 2>/dev/null")])
                    let after = await getDirectorySize(goCacheDir)
                    extraFreedBytes += max(0, before - after)
                }
            }
        }

        if cleanModCache {
            let goModPath = "\(home)/go/pkg/mod/cache"
            if fm.fileExists(atPath: goModPath) {
                let (gf, gi) = try await cleanContents(of: goModPath, dryRun: dryRun, progress: progress)
                if dryRun { emitFileItem(gi, category: "Language caches", parentName: "Go Module Cache", progress: progress) }
                extraFreedBytes += gf
            }
        }

        let extraMB = Int(extraFreedBytes / (1024 * 1024))
        if extraMB > 0 || extraFreedBytes > 0 {
            if !results.isEmpty {
                results[0] = CleanupEngineResult(label: results[0].label, freedMB: results[0].freedMB + extraMB, failedCount: results[0].failedCount)
            } else {
                results.append(CleanupEngineResult(label: "Language caches", freedMB: extraMB))
            }
        }
        return results
    }

    // MARK: 14. User Logs

    func cleanUserLogs(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning user logs..."))
        var freed: Int64 = 0

        // Recursive removal of old files (matching bash script behavior)
        let (lf, li) = try await cleanOldFilesRecursive(in: "\(home)/Library/Logs", olderThanDays: 7, dryRun: dryRun, progress: progress)
        freed += lf
        if dryRun { emitFileItem(li, category: "User logs", parentName: nil, progress: progress) }

        let logsPaths = [
            "\(home)/Library/Logs/DiagnosticReports",
            "\(home)/Library/Logs/CrashReporter",
            "\(home)/Library/Application Support/CrashReporter",
            "\(home)/Library/Logs/PanicReporter",
            "\(home)/Library/Logs/Retired",
            "\(home)/Library/Logs/MobileSlideshows",
            "\(home)/Library/Logs/stackshot",
        ]
        for path in logsPaths {
            guard fm.fileExists(atPath: path) else { continue }
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "User logs", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("User logs total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "User logs", freedMB: mb))
        return [CleanupEngineResult(label: "User logs", freedMB: mb)]
    }

    // MARK: 15. System Caches

    func cleanSystemCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        return try await cleanFromEmbeddedPaths(.systemCaches, label: "System caches", dryRun: dryRun, progress: progress)
    }

    // MARK: 16. App Containers

    func cleanAppContainers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning app containers..."))
        var freed: Int64 = 0

        let containerDirs = [
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
        ]

        let cacheSubdirs = [
            "Data/Library/Caches",
            "Data/Library/Logs",
            "Data/tmp",
            "Library/Caches",  // for Group Containers
        ]

        for containersPath in containerDirs {
            guard fm.fileExists(atPath: containersPath) else { continue }
            let containers: [String]
            do {
                containers = try fm.contentsOfDirectory(atPath: containersPath)
            } catch {
                let ns = error as NSError
                if (ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)))
                    || (ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoPermissionError || ns.code == NSFileWriteNoPermissionError)) {
                    progress?(.log("  \(shortPath(containersPath)) — access denied by macOS (Full Disk Access required)"))
                } else {
                    progress?(.log("  \(shortPath(containersPath)) — read failed: \(error.localizedDescription)"))
                }
                continue
            }
            let containerCount = containers.count
            progress?(.log("  Found \(containerCount) containers in \(shortPath(containersPath))"))
            var scannedCount = 0
            for container in containers {
                try Task.checkCancellation()
                // Skip Apple system containers
                if container.hasPrefix("com.apple.") || container.hasPrefix("group.com.apple.") {
                    continue
                }
                // Skip heavy containers (Docker, VMs) — virtual disks cause timeouts
                if Self.isHeavyContainer(container) {
                    progress?(.log("  \(container) — skipped (heavy container)"))
                    continue
                }
                let containerPath = "\(containersPath)/\(container)"
                for subdir in cacheSubdirs {
                    let dataCaches = "\(containerPath)/\(subdir)"
                    if fm.fileExists(atPath: dataCaches) {
                        scannedCount += 1
                        let (f, item) = try await cleanContents(of: dataCaches, dryRun: dryRun, progress: progress)
                        freed += f
                        if dryRun { emitFileItem(item, category: "App containers", parentName: nil, progress: progress) }
                    }
                }
            }
            progress?(.log("  Scanned \(scannedCount) containers with caches"))
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("App containers total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "App container caches", freedMB: mb))
        return [CleanupEngineResult(label: "App containers", freedMB: mb)]
    }

    // MARK: 17. Dotfile Caches

    func cleanDotfileCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        return try await cleanFromEmbeddedPaths(.dotfileCaches, label: "Dotfile caches", dryRun: dryRun, progress: progress)
    }

    // MARK: 18. Scattered Junk

    func cleanScatteredJunk(dryRun: Bool, cleanDSStore: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let localFM = FileManager.default
        let home = fileSystemContext.homePath
        progress?(.log("Scanning scattered junk..."))

        let scanDirs = [
            home,
            "/Applications",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Desktop",
            "\(home)/Projects",
            "\(home)/Developer",
            "\(home)/dev",
            "\(home)/code",
            "\(home)/repos"
        ].filter { localFM.fileExists(atPath: $0) }

        let scanner = PosixScanner()
        var foundItems: [ScatteredItem] = []
        var scannedCount = 0

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date().addingTimeInterval(-7 * 86400)
        let windowsMetaNames: Set<String> = ["Thumbs.db", "desktop.ini", "ehthumbs.db"]

        do {
            for await batch in scanner.scanParallel(
                roots: scanDirs,
                config: .init(
                    excludedPrefixes: ["/Library/", "/.Trash/", "/.git/", "/.vscode/", "/.idea/"],
                    maxDepth: nil,
                    batchSize: 1000
                ),
                progress: { scanned, _ in
                    progress?(.log("  Scanned \(scanned) files..."))
                }
            ) {
                try Task.checkCancellation()

                for entry in batch {
                    scannedCount += 1

                    if entry.path.contains("/.vscode/") || entry.path.contains("/.idea/")
                        || entry.path.hasSuffix("/.vscode") || entry.path.hasSuffix("/.idea") {
                        continue
                    }

                    if entry.name == ".DS_Store" {
                        if cleanDSStore {
                            foundItems.append(.dsStore(entry.path))
                            if dryRun {
                                emitFileItem(
                                    await makeFileItemForPath(entry.path, fm: localFM),
                                    category: "Scattered junk",
                                    parentName: ".DS_Store",
                                    progress: progress
                                )
                            }
                        }
                        continue
                    }

                    if entry.isDirectory && entry.name == "__MACOSX" {
                        foundItems.append(.macosxDir(entry.path))
                        if dryRun {
                            emitFileItem(
                                await makeFileItemForPath(entry.path, fm: localFM),
                                category: "Scattered junk",
                                parentName: "__MACOSX",
                                progress: progress
                            )
                        }
                        continue
                    }

                    if windowsMetaNames.contains(entry.name) {
                        foundItems.append(.windowsMeta(entry.path))
                        if dryRun {
                            emitFileItem(
                                await makeFileItemForPath(entry.path, fm: localFM),
                                category: "Scattered junk",
                                parentName: "Windows metadata",
                                progress: progress
                            )
                        }
                        continue
                    }

                    if !entry.isDirectory && entry.name.hasSuffix(".log") {
                        if let attrs = try? localFM.attributesOfItem(atPath: entry.path),
                           let modDate = attrs[.modificationDate] as? Date,
                           modDate < cutoffDate,
                           let size = attrs[.size] as? Int64,
                           size > 1024 * 1024 {
                            foundItems.append(.oldLogFile(entry.path, size))
                            if dryRun {
                                emitFileItem(
                                    await makeFileItemForPath(entry.path, fm: localFM, size: size),
                                    category: "Scattered junk",
                                    parentName: "Old logs",
                                    progress: progress
                                )
                            }
                        }
                        continue
                    }

                    if entry.isSymlink {
                        let dirOfSymlink = (entry.path as NSString).deletingLastPathComponent
                        let target = try? localFM.destinationOfSymbolicLink(atPath: entry.path)
                        if let target = target {
                            let resolvedTarget: String
                            if (target as NSString).isAbsolutePath {
                                resolvedTarget = target
                            } else {
                                resolvedTarget = (dirOfSymlink as NSString).appendingPathComponent(target)
                            }
                            if !localFM.fileExists(atPath: resolvedTarget) {
                                foundItems.append(.brokenSymlink(entry.path))
                                if dryRun {
                                    emitFileItem(
                                        await makeFileItemForPath(entry.path, fm: localFM),
                                        category: "Scattered junk",
                                        parentName: "Broken symlinks",
                                        progress: progress
                                    )
                                }
                            }
                        } else {
                            foundItems.append(.brokenSymlink(entry.path))
                            if dryRun {
                                emitFileItem(
                                    await makeFileItemForPath(entry.path, fm: localFM),
                                    category: "Scattered junk",
                                    parentName: "Broken symlinks",
                                    progress: progress
                                )
                            }
                        }
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            progress?(.log("  Warning: scattered junk scan encountered error: \(error.localizedDescription)"))
        }

        var freed: Int64 = 0
        for item in foundItems {
            try Task.checkCancellation()
            switch item {
            case .dsStore(let path), .windowsMeta(let path), .brokenSymlink(let path):
                let (f, _) = (try? await removeFile(path, dryRun: dryRun, progress: nil)) ?? (0, nil)
                freed += f
            case .macosxDir(let path):
                let (f, _) = (try? await removeDirectory(path, dryRun: dryRun, progress: nil)) ?? (0, nil)
                freed += f
            case .oldLogFile(let path, _):
                let (f, _) = (try? await removeFile(path, dryRun: dryRun, progress: nil)) ?? (0, nil)
                freed += f
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Scattered junk total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Scattered junk", freedMB: mb))
        return [CleanupEngineResult(label: "Scattered junk", freedMB: mb)]
    }

    private func makeFileItemForPath(_ path: String, fm: FileManager, size: Int64? = nil) async -> CleanupFileItem? {
        let attrs = try? fm.attributesOfItem(atPath: path)
        let modDate = attrs?[.modificationDate] as? Date
        let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
        let itemSize: Int64
        if let size {
            itemSize = size
        } else {
            let dirSize = await getDirectorySize(path)
            itemSize = dirSize > 0 ? dirSize : (attrs?[.size] as? Int64) ?? 0
        }
        return CleanupFileItem(path: path, sizeBytes: itemSize, modificationDate: modDate, isDirectory: isDir)
    }

    private enum ScatteredItem: Sendable {
        case dsStore(String)
        case macosxDir(String)
        case oldLogFile(String, Int64)
        case windowsMeta(String)
        case brokenSymlink(String)
    }

    // MARK: - Heavy Directory Skip List

    /// Paths to skip during recursive scans (virtual disks, VM images, Docker, etc.)
    /// These directories contain sparse files or virtual disks that cause timeout during size calculation.
    static let heavyDirectoryPaths: Set<String> = [
        "Library/Containers/com.docker.docker",
        "Library/Containers/dev.orbstack.OrbStack",
        "Library/Containers/com.vmware.fusion",
        "Library/Containers/com.parallels.desktop.console",
        "Library/Containers/com.utmapp.UTM",
        "Library/Containers/org.virtualbox.app.VirtualBox",
        "Library/Application Support/Docker",
        "Library/Application Support/OrbStack",
        "Library/Application Support/VMware",
        "Library/Application Support/Parallels",
        "Library/Application Support/UTM",
        "Library/Application Support/VirtualBox",
        "Library/Caches/com.docker.docker",
        "Library/Caches/dev.orbstack.OrbStack",
        "Library/Group Containers/group.com.docker",
        "/.docker",
        "/.orbstack",
        "/.vagrant.d",
        "/VirtualBox VMs/",
        "VMware Fusion",
        "Parallels Desktop",
    ]

    /// Checks if a path should be skipped due to known heavy content.
    private static func isHeavyDirectory(_ path: String) -> Bool {
        let normalizedPath = path.replacingOccurrences(of: "//", with: "/")
        for heavyPath in heavyDirectoryPaths {
            if normalizedPath.contains(heavyPath) {
                return true
            }
        }
        return false
    }

    // MARK: 21. Large Files

    func cleanLargeFiles(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning large files (review-only; DMG/PKG → Installer Packages)..."))
        var totalFound: Int64 = 0
        var items: [(String, Int64)] = []

        // Old archives in Downloads, Desktop, Documents (installers → .installerPackages)
        let downloadDirs = ["\(home)/Downloads", "\(home)/Desktop", "\(home)/Documents"]
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 86400)
        for downloadDir in downloadDirs {
            guard fm.fileExists(atPath: downloadDir) else { continue }
            let contents = try? fm.contentsOfDirectory(atPath: downloadDir)
            var scannedCount = 0
            for file in (contents ?? []) {
                let ext = (file as NSString).pathExtension.lowercased()
                if ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext) {
                    let filePath = "\(downloadDir)/\(file)"
                    if let attrs = try? fm.attributesOfItem(atPath: filePath),
                       let modDate = attrs[.modificationDate] as? Date,
                       modDate < cutoffDate,
                       let size = attrs[.size] as? Int64, size > 100 * 1024 * 1024 {
                        // Installer .zip archives belong exclusively to .installerPackages.
                        if ext == "zip", ZipCentralDirectoryInspector.containsInstallerPayload(at: filePath, fileSize: size) {
                            continue
                        }
                        items.append(("\(downloadDir.replacingOccurrences(of: home, with: "~"))/\(file)", size))
                        totalFound += size
                        if dryRun {
                            emitFileItem(CleanupFileItem(path: filePath, sizeBytes: size, modificationDate: modDate, isDirectory: false), category: "Large files", parentName: "Large files", progress: progress)
                        }
                    }
                }
                scannedCount += 1
            }
            progress?(.log("  Checked \(scannedCount) files in \(downloadDir.replacingOccurrences(of: home, with: "~"))"))
        }

        // IPSW firmware files (run off the actor executor and skip Library/dev trees)
        progress?(.log("  Scanning for IPSW firmware files..."))
        let ipswMatches: [(path: String, size: Int64, label: String)] = await Task.detached(priority: .utility) {
            let localFM = FileManager.default
            let skipTopLevel: Set<String> = ["Library", ".Trash", ".gradle", ".pub-cache", ".cargo", ".rustup", ".npm", ".cache"]
            let skipAnyLevel: Set<String> = [".git", "node_modules", ".build", "DerivedData"]
            let searchDirs = [home, "/tmp"]
            var found: [(String, Int64, String)] = []

            for dir in searchDirs {
                if Task.isCancelled { break }
                guard localFM.fileExists(atPath: dir),
                      let enumerator = localFM.enumerator(atPath: dir) else { continue }

                while let item = enumerator.nextObject() as? String {
                    if Task.isCancelled { break }
                    let fullPath = "\(dir)/\(item)"
                    let lastName = (item as NSString).lastPathComponent
                    if (dir == home && skipTopLevel.contains(item))
                        || skipAnyLevel.contains(lastName)
                        || lastName.hasSuffix(".photoslibrary")
                        || Self.isHeavyDirectory(fullPath) {
                        var isDir: ObjCBool = false
                        localFM.fileExists(atPath: fullPath, isDirectory: &isDir)
                        if isDir.boolValue { enumerator.skipDescendants() }
                        continue
                    }
                    if (item as NSString).pathExtension.lowercased() == "ipsw" {
                        if let attrs = try? localFM.attributesOfItem(atPath: fullPath),
                           let size = attrs[.size] as? Int64, size > 100 * 1024 * 1024 {
                            found.append((fullPath, size, "IPSW: \(item)"))
                        }
                    }
                }
            }
            return found
        }.value

        try Task.checkCancellation()
        for match in ipswMatches {
            items.append((match.label, match.size))
            totalFound += match.size
            if dryRun {
                emitFileItem(CleanupFileItem(path: match.path, sizeBytes: match.size, modificationDate: nil, isDirectory: false), category: "Large files", parentName: "Large files", progress: progress)
            }
        }

        let mb = Int(totalFound / (1024 * 1024))
        if !items.isEmpty {
            let detail = items.prefix(5).map { "\($0.0): \(Self.formatBytes($0.1))" }.joined(separator: ", ")
            progress?(.log("  Large files found: \(detail)"))
        } else {
            progress?(.log("  No large files found"))
        }
        progress?(.log("Large files total: \(Self.formatBytes(totalFound)) — select explicitly; engine does not delete"))
        progress?(.result(label: "Large files", freedMB: dryRun ? mb : 0))
        return [CleanupEngineResult(
            label: "Large files",
            freedMB: dryRun ? mb : 0,
            freedBytes: dryRun ? totalFound : 0,
            removedCount: 0,
            skippedCount: 0,
            failedCount: 0
        )]
    }

    // MARK: 22. Dynamic Cache Discovery

    func cleanDynamicCacheDiscovery(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        let cachesDir = "\(home)/Library/Caches"
        progress?(.log("Scanning ~/Library/Caches for large directories..."))
        var freed: Int64 = 0
        var autoCleanableItems: [(String, Int64)] = []
        var reviewItems: [(String, Int64)] = []

        guard fm.fileExists(atPath: cachesDir) else {
            return [CleanupEngineResult(label: "Dynamic cache discovery", freedMB: 0)]
        }

        let entries = (try? fm.contentsOfDirectory(atPath: cachesDir)) ?? []
        for entry in entries {
            try Task.checkCancellation()

            // Skip heavy containers (Docker, VMs) — virtual disks cause timeouts
            if Self.isHeavyContainer(entry) {
                progress?(.log("  \(entry) — skipped (heavy container)"))
                continue
            }

            let entryPath = "\(cachesDir)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entryPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let size = await getDirectorySizeWithTimeout(entryPath, timeout: .seconds(5))
            if size < 5 * 1024 * 1024 { // < 5 MB, skip
                continue
            }

            // Check if it's a known-safe reverse-DNS pattern for auto-clean
            // Apple caches (com.apple.*) are safe at any size >= 5 MB
            // Other reverse-DNS caches need >= 20 MB (lowered from 50 MB for better coverage)
            let isAppleCache = entry.hasPrefix("com.apple.")
            let isSafePattern = entry.contains(".") && (entry.hasPrefix("com.") || entry.hasPrefix("org.") || entry.hasPrefix("io.") || entry.hasPrefix("net.") || entry.hasPrefix("co.") || entry.hasPrefix("ai.") || entry.hasPrefix("ru."))
            let minSizeForAutoClean: Int64 = isAppleCache ? 5 * 1024 * 1024 : 20 * 1024 * 1024

            if dryRun {
                // In scan mode: show ALL entries >= 5 MB
                let isAutoClean = isSafePattern && size >= minSizeForAutoClean
                if isAutoClean {
                    autoCleanableItems.append((entry, size))
                    progress?(.log("  ⊘ \(entry) — \(Self.formatBytes(size)) (would auto-clean)"))
                    emitFileItem(CleanupFileItem(path: entryPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Dynamic cache discovery", parentName: "Auto-cleanable", progress: progress)
                } else {
                    reviewItems.append((entry, size))
                    progress?(.log("  ℹ \(entry) — \(Self.formatBytes(size)) (review manually)"))
                    progress?(.preview(
                        label: "\(entry) — \(shortPath(entryPath))",
                        sizeMB: Int(size / (1024 * 1024)),
                        deletable: false,
                        parent: "Review manually",
                        description: "Review this cache manually before deleting it."
                    ))
                }
            } else if isSafePattern && size >= minSizeForAutoClean {
                if skipsUnselected(entryPath, dryRun: dryRun) {
                    progress?(.log("  \(entry) — skipped (not selected)"))
                    continue
                }
                do {
                    let (removedFreed, _) = try await fileActor.removeDirectory(entryPath, dryRun: false, bypassTrash: CleanupEngine.currentBypassTrash, progress: progress)
                    freed += removedFreed
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    progress?(.log("  Skipped \(entry) — \(error.localizedDescription)"))
                }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        if !autoCleanableItems.isEmpty {
            let detail = autoCleanableItems.prefix(5).map { "\($0.0): \(Self.formatBytes($0.1))" }.joined(separator: ", ")
            progress?(.log("  Auto-cleanable: \(detail)"))
        }
        if !reviewItems.isEmpty {
            let detail = reviewItems.prefix(5).map { "\($0.0): \(Self.formatBytes($0.1))" }.joined(separator: ", ")
            progress?(.log("  Review manually: \(detail)"))
        }
        progress?(.log("Dynamic cache discovery total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Dynamic cache discovery", freedMB: mb))
        return [CleanupEngineResult(label: "Dynamic cache discovery", freedMB: mb)]
    }

    // MARK: 23. Time Machine Snapshots

    func cleanTimeMachineSnapshots(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Scanning Time Machine local snapshots..."))

        guard await commandRunner.commandExists("tmutil") else {
            progress?(.log("  tmutil not found, skipped"))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
        }

        let snapshots = await TimeMachineScanner.listLocalSnapshots()
        let purgeableMB = TimeMachineScanner.getPurgeableSpaceMB()

        progress?(.log("  Found \(snapshots.count) local snapshots (purgeable: ~\(purgeableMB) MB)"))

        if dryRun {
            for snap in snapshots {
                progress?(.log("  ⊘ \(snap.name)"))
            }
            emitFileItem(CleanupFileItem(path: "command://tmutil/thin", sizeBytes: Int64(purgeableMB) * 1024 * 1024, modificationDate: nil, isDirectory: false), category: "Time Machine Snapshots", parentName: nil, isSelected: false, isCommandBacked: true, progress: progress)
            progress?(.result(label: "Time Machine Snapshots", freedMB: purgeableMB))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: purgeableMB)]
        }

        if skipsUnselected("command://tmutil/thin", dryRun: dryRun) {
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0, skippedCount: 1)]
        }

        if snapshots.isEmpty {
            progress?(.log("  No local snapshots to thin"))
            progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
        }

        let availableBefore = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity ?? 0
        let purgeBytes = Int64(purgeableMB) * 1024 * 1024
        guard purgeBytes > 0 else {
            progress?(.log("  No purgeable snapshot space"))
            progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
        }

        do {
            try Task.checkCancellation()
            let result = try await commandRunner.run(
                command: "/usr/bin/tmutil",
                arguments: ["thinlocalsnapshots", "/", "\(purgeBytes)", "4"]
            )
            guard result.exitCode == 0 else {
                progress?(.log("  Requires administrator privileges to thin Time Machine local snapshots"))
                progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
                return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
            }
            let availableAfter = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity ?? 0
            let freedBytes = max(0, availableAfter - availableBefore)
            let freedMB = Int(freedBytes / (1024 * 1024))
            progress?(.log("  ✓ Thinned local snapshots (freed ~\(freedMB) MB)"))
            progress?(.result(label: "Time Machine Snapshots", freedMB: freedMB))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: freedMB, freedBytes: Int64(freedBytes))]
        } catch {
            progress?(.log("  ✗ Failed to thin snapshots: \(error.localizedDescription)"))
            progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
        }
    }

    // MARK: 24. iOS Backups

    func cleanIOSBackups(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning iOS backups..."))

        let backupDir = "\(home)/Library/Application Support/MobileSync/Backup"
        let (freed, item) = try await cleanContents(of: backupDir, dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "iOS Backups", parentName: nil, isSelected: false, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "iOS Backups", freedMB: mb))
        return [CleanupEngineResult(label: "iOS Backups", freedMB: mb, freedBytes: freed)]
    }

    // MARK: 25. Mail Downloads

    func cleanMailDownloads(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Mail downloads..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/Library/Mail Downloads",
            "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        ]

        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Mail Downloads", parentName: nil, isSelected: false, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Mail Downloads", freedMB: mb))
        return [CleanupEngineResult(label: "Mail Downloads", freedMB: mb)]
    }

    // MARK: 26. Saved Application State

    func cleanSavedAppState(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning saved application state..."))

        let (freed, item) = try await cleanContents(of: "\(home)/Library/Saved Application State", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Saved Application State", parentName: nil, isSelected: false, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Saved Application State", freedMB: mb))
        return [CleanupEngineResult(label: "Saved Application State", freedMB: mb)]
    }

    // MARK: 27. Crash Reporter

    func cleanCrashReporter(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning crash reports..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/Library/Application Support/CrashReporter",
            "\(home)/Library/Logs/DiagnosticReports",
        ]

        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Crash Reporter", parentName: nil, progress: progress) }
        }

        // System path — skip in dry-run (cannot read), attempt only in actual cleanup
        if !dryRun {
            let systemPath = "/Library/Logs/DiagnosticReports"
            do {
                let (f, item) = try await cleanContents(of: systemPath, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Crash Reporter", parentName: nil, progress: progress) }
            } catch is SafetyError {
                progress?(.log("  \(shortPath(systemPath)) — protected, skipped"))
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Crash Reporter", freedMB: mb))
        return [CleanupEngineResult(label: "Crash Reporter", freedMB: mb)]
    }

    // MARK: 28. AssetsV2 / iWork Templates

    func cleanAssetsV2(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning AssetsV2 / iWork templates..."))

        let (freed, item) = try await cleanContents(of: "\(home)/Library/Application Support/AssetsV2", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "AssetsV2 / iWork Templates", parentName: nil, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "AssetsV2 / iWork Templates", freedMB: mb))
        return [CleanupEngineResult(label: "AssetsV2 / iWork Templates", freedMB: mb)]
    }

    // MARK: 29. CloudKit Cache

    func cleanCloudKitCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning CloudKit cache..."))

        let (freed, item) = try await cleanContents(of: "\(home)/Library/Caches/CloudKit", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "CloudKit Cache", parentName: nil, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "CloudKit Cache", freedMB: mb))
        return [CleanupEngineResult(label: "CloudKit Cache", freedMB: mb)]
    }

    // MARK: 30. Swift Package Manager Cache

    func cleanSwiftPMCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Scanning SwiftPM cache..."))
        var freed: Int64 = 0

        let paths = resolveSubpaths(EmbeddedCleanupPaths.swiftPMCacheSubpaths)

        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Swift Package Manager Cache", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Swift Package Manager Cache", freedMB: mb))
        return [CleanupEngineResult(label: "Swift Package Manager Cache", freedMB: mb)]
    }

    // MARK: 31. Carthage Cache

    func cleanCarthageCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Scanning Carthage cache..."))
        var freed: Int64 = 0

        let paths = resolveSubpaths(EmbeddedCleanupPaths.carthageCacheSubpaths)

        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun, let item {
                let described = path.hasSuffix("/.cocoapods/repos")
                    ? CleanupFileItem(
                        path: item.path,
                        sizeBytes: item.sizeBytes,
                        modificationDate: item.modificationDate,
                        isDirectory: item.isDirectory,
                        description: "cleanup_desc_cocoapods_repos".localized
                    )
                    : item
                emitFileItem(described, category: "Carthage Cache", parentName: nil, progress: progress)
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Carthage Cache", freedMB: mb))
        return [CleanupEngineResult(label: "Carthage Cache", freedMB: mb)]
    }

    // MARK: 32. Steam Cache

    func cleanSteamCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Steam cache..."))
        var freed: Int64 = 0

        let steamBase = "\(home)/Library/Application Support/Steam"
        let subdirs = ["appcache", "depotcache", "logs", "steamapps/shadercache", "steamapps/temp", "steamapps/download"]

        for sub in subdirs {
            let path = "\(steamBase)/\(sub)"
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Steam Cache", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Steam Cache", freedMB: mb))
        return [CleanupEngineResult(label: "Steam Cache", freedMB: mb)]
    }

    // MARK: 33. Microsoft Teams Cache

    func cleanTeamsCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Only regenerable cache dirs — never Service Worker registration/state or Local/Session Storage.
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Microsoft Teams cache..."))
        var freed: Int64 = 0

        let teamsSubdirs = [
            "Cache", "Code Cache", "GPUCache",
            "Service Worker/CacheStorage", "Service Worker/ScriptCache",
        ]

        let allTeamsBases = [
            "\(home)/Library/Application Support/Microsoft/Teams",
            "\(home)/Library/Application Support/Microsoft/Teams2",
        ]

        for teamsBase in allTeamsBases {
            guard fm.fileExists(atPath: teamsBase) else { continue }
            progress?(.log("  Found: \(shortPath(teamsBase))"))
            for sub in teamsSubdirs {
                let path = "\(teamsBase)/\(sub)"
                let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Microsoft Teams Cache", parentName: nil, progress: progress) }
            }
        }

        for cachePath in [
            "\(home)/Library/Caches/com.microsoft.teams2",
            "\(home)/Library/Caches/com.microsoft.teams",
        ] {
            let (f, item) = try await cleanContents(of: cachePath, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Microsoft Teams Cache", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Microsoft Teams Cache", freedMB: mb))
        return [CleanupEngineResult(label: "Microsoft Teams Cache", freedMB: mb)]
    }

    // MARK: 34. Adobe Caches

    func cleanAdobeCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Adobe caches..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/Library/Caches/Adobe",
            "\(home)/Library/Application Support/Adobe/Common/Media Cache"
        ]

        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Adobe Caches", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Adobe Caches", freedMB: mb))
        return [CleanupEngineResult(label: "Adobe Caches", freedMB: mb)]
    }

    // MARK: 35. Chrome Extra Caches

    func cleanChromeExtraCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Chrome extra caches..."))
        var freed: Int64 = 0

        let chromeBase = "\(home)/Library/Application Support/Google/Chrome/Default"
        let chromeBaseRoot = "\(home)/Library/Application Support/Google/Chrome"
        // Session Storage / Service Worker registration intentionally excluded.
        let subdirs = [
            "Cache", "Code Cache", "GPUCache",
            "Service Worker/CacheStorage", "Service Worker/ScriptCache",
        ]
        let rootSubdirs = ["GrShaderCache", "ShaderCache"]

        // Check if Chrome is running and warn
        let isChromeRunning = await isAppRunning(bundleIdentifier: "com.google.Chrome")
        if isChromeRunning {
            progress?(.log("  ⚠ Chrome is running — some cache files may be locked"))
        }

        for sub in subdirs {
            let path = "\(chromeBase)/\(sub)"
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Chrome Extra Caches", parentName: nil, progress: progress) }
        }
        // Also clean Chrome root-level GPU shader caches
        for sub in rootSubdirs {
            let path = "\(chromeBaseRoot)/\(sub)"
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Chrome Extra Caches", parentName: "Root shader cache", progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Chrome Extra Caches", freedMB: mb))
        return [CleanupEngineResult(label: "Chrome Extra Caches", freedMB: mb)]
    }

    private func isAppRunning(bundleIdentifier: String) async -> Bool {
        let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "pgrep -x \(bundleIdentifier) >/dev/null 2>&1"])
        return result?.exitCode == 0
    }

    // MARK: 36. Launch Agents (user)

    // MARK: 41. Shared File Lists

    func cleanSharedFileLists(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning shared file lists (recent items only)..."))
        let dir = "\(home)/Library/Application Support/com.apple.sharedfilelist"
        guard fm.fileExists(atPath: dir) else {
            return [CleanupEngineResult(label: "Shared File Lists", freedMB: 0)]
        }

        let safePrefixes = [
            "com.apple.LSSharedFileList.RecentDocuments",
            "com.apple.LSSharedFileList.RecentApplications",
            "com.apple.LSSharedFileList.RecentServers",
            "com.apple.LSSharedFileList.RecentHosts"
        ]

        var freed: Int64 = 0
        let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        for entry in entries {
            let isSafe = safePrefixes.contains { entry.hasPrefix($0) }
            guard isSafe else { continue }
            let fullPath = "\(dir)/\(entry)"
            do {
                let (f, item) = try await removeFile(fullPath, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Shared File Lists", parentName: nil, isSelected: false, progress: progress) }
            } catch is SafetyError {
                progress?(.log("  \(shortPath(fullPath)) — protected, skipped"))
            }
        }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Shared File Lists", freedMB: mb))
        return [CleanupEngineResult(label: "Shared File Lists", freedMB: mb, freedBytes: freed)]
    }

    // MARK: 43. Photos Cache

    func cleanPhotosCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Photos cache..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/Containers/com.apple.Photos/Data/Library/Caches", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Photos Cache", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Photos Cache", freedMB: mb))
        return [CleanupEngineResult(label: "Photos Cache", freedMB: mb)]
    }

    // MARK: 47. Garmin / Fitbit

    func cleanGarminFitbit(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Garmin / Fitbit caches..."))
        var freed: Int64 = 0
        let paths = [
            "\(home)/Library/Caches/com.garmin.connectiq",
            "\(home)/Library/Caches/com.fitbit.Fitbit-OS-Simulator",
        ]
        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Garmin / Fitbit", parentName: nil, progress: progress) }
        }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Garmin / Fitbit", freedMB: mb))
        return [CleanupEngineResult(label: "Garmin / Fitbit", freedMB: mb)]
    }

    // MARK: 48. Old Backups

    func cleanOldBackups(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Review-only: surface aged backup-like files for explicit selection.
        // Never wholesale-clean ~/Backups. Engine never deletes — coordinator removes selected paths only.
        let home = fileSystemContext.homePath
        let minAgeDays = 30
        let cutoff = Date().addingTimeInterval(TimeInterval(-minAgeDays * 24 * 60 * 60))
        let roots = ["Desktop", "Downloads", "Documents"].map { "\(home)/\($0)" }
        progress?(.log("Scanning old backups (age ≥ \(minAgeDays)d, review-only; ~/Backups never wholesale)..."))

        var totalBytes: Int64 = 0
        var found = 0
        var skipped = 0

        for root in roots {
            try Task.checkCancellation()
            guard fm.fileExists(atPath: root) else { continue }
            let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
            for name in entries {
                try Task.checkCancellation()
                let path = "\(root)/\(name)"
                let lower = name.lowercased()
                let looksLikeBackup =
                    lower.hasSuffix(".backup")
                    || lower.hasSuffix(".bak")
                    || lower.hasSuffix(".old")
                    || lower.hasSuffix("~")
                guard looksLikeBackup else {
                    skipped += 1
                    continue
                }
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modified = attrs[.modificationDate] as? Date,
                      modified < cutoff else {
                    skipped += 1
                    continue
                }
                if safetyManager.isSymlinkDirectory(URL(fileURLWithPath: path)) {
                    skipped += 1
                    continue
                }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: path, isDirectory: &isDir)
                let size: Int64
                if isDir.boolValue {
                    size = await getDirectorySize(path)
                } else if let num = try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber {
                    size = num.int64Value
                } else {
                    size = 0
                }
                guard size > 0 else {
                    skipped += 1
                    continue
                }
                found += 1
                totalBytes += size
                progress?(.fileItem(
                    path: path,
                    sizeBytes: size,
                    modificationDate: modified,
                    isDirectory: isDir.boolValue,
                    category: "Old Backups",
                    parentName: "Old Backups"
                ))
                progress?(.log("  review: \(shortPath(path)) — \(Self.formatBytes(size)) (opt-in)"))
            }
        }

        let mb = Int(totalBytes / (1024 * 1024))
        progress?(.log("Old Backups: found=\(found) skipped=\(skipped) — select explicitly; engine does not delete"))
        progress?(.result(label: "Old Backups", freedMB: dryRun ? mb : 0))
        return [CleanupEngineResult(
            label: "Old Backups",
            freedMB: dryRun ? mb : 0,
            freedBytes: dryRun ? totalBytes : 0,
            removedCount: 0,
            skippedCount: skipped,
            failedCount: 0
        )]
    }

    // MARK: 49. AI Models / LLM user content

    func cleanAIModels(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Review-only: Ollama/HF/LM Studio/Jan/mlx/torch model stores are user_content.
        // Engine never deletes — coordinator trashes only explicitly selected leaves.
        let home = fileSystemContext.homePath
        let label = "AI Models"
        progress?(.log("Scanning AI / LLM model stores (user_content, opt-in)..."))

        var totalBytes: Int64 = 0
        var found = 0
        var skipped = 0
        var seen = Set<String>()

        for template in GeneratedCleanupPaths.aiUserContentTemplates() {
            try Task.checkCancellation()
            let resolved = PathToken.home.resolveTemplate(template, home: home)
            for path in CleanupPathExpander.expand(resolved, home: home, fileManager: fm) {
                try Task.checkCancellation()
                guard seen.insert(path).inserted else { continue }
                let size = await getDirectorySize(path)
                guard size > 0 else {
                    skipped += 1
                    continue
                }
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: path, isDirectory: &isDir)
                let attrs = try? fm.attributesOfItem(atPath: path)
                let modified = attrs?[.modificationDate] as? Date
                found += 1
                totalBytes += size
                progress?(.fileItem(
                    path: path,
                    sizeBytes: size,
                    modificationDate: modified,
                    isDirectory: isDir.boolValue,
                    category: label,
                    parentName: label
                ))
                progress?(.log("  review: \(shortPath(path)) — \(Self.formatBytes(size)) (opt-in)"))
            }
        }

        let mb = Int(totalBytes / (1024 * 1024))
        progress?(.log("AI Models: found=\(found) skipped=\(skipped) — select explicitly; engine does not delete"))
        progress?(.result(label: label, freedMB: dryRun ? mb : 0))
        return [CleanupEngineResult(
            label: label,
            freedMB: dryRun ? mb : 0,
            freedBytes: dryRun ? totalBytes : 0,
            removedCount: 0,
            skippedCount: skipped,
            failedCount: 0
        )]
    }

    // MARK: 49b. Installer packages (DMG / PKG / ISO / installer ZIP)

    func cleanInstallerPackages(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let skipHomebrew: Bool
        if CleanupEngine.currentPlannedCategories.contains(.packageManagers) {
            skipHomebrew = await commandExists("brew")
        } else {
            skipHomebrew = false
        }
        return try await scanInstallerPackages(dryRun: dryRun, skipHomebrewDownloads: skipHomebrew, progress: progress)
    }

    func scanInstallerPackages(
        dryRun: Bool,
        skipHomebrewDownloads: Bool = false,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?
    ) async throws -> [CleanupEngineResult] {
        // Review-only: surface forgotten installers for explicit selection.
        let home = fileSystemContext.homePath
        let label = "Installer Packages"
        let minAgeDays = 7
        let minImageSize: Int64 = 20 * 1024 * 1024 // 20 MB — skip tiny stubs
        let cutoff = Date().addingTimeInterval(TimeInterval(-minAgeDays * 24 * 60 * 60))
        progress?(.log("Scanning installer packages (dmg/pkg/iso/zip; opt-in)..."))

        let installedApps = Self.installedApplicationStemNames(home: home, fileManager: fm)
        var sources: [(dir: String, sourceName: String, allowInstallerZip: Bool)] = [
            ("\(home)/Downloads", "Downloads", true),
            ("\(home)/Desktop", "Desktop", true),
            ("\(home)/Documents", "Documents", true),
            ("\(home)/Library/Application Support/Slack/Downloads", "Slack", false),
            ("\(home)/Library/Containers/com.tinyspeck.slackmacgap/Data/Downloads", "Slack", false),
            ("\(home)/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/Downloads", "Slack", false),
            ("\(home)/Library/Application Support/discord/Downloads", "Discord", false),
            ("\(home)/Library/Containers/net.whatsapp.WhatsApp/Data/Downloads", "WhatsApp", false),
            ("\(home)/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Application Support/WhatsApp/Downloads", "WhatsApp", false),
            ("\(home)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media", "WhatsApp", false),
        ]

        let telegramTemplates = [
            "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/*/account-*/postbox/media",
            "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/account-*/postbox/media",
        ]
        for template in telegramTemplates {
            for dir in CleanupPathExpander.expand(template, home: home, fileManager: fm) {
                sources.append((dir, "Telegram", false))
            }
        }

        if !skipHomebrewDownloads {
            sources.append(("\(home)/Library/Caches/Homebrew/downloads", "Homebrew", false))
        }

        var totalBytes: Int64 = 0
        var found = 0
        var skipped = 0
        var seenPaths = Set<String>()
        let imageExtensions: Set<String> = ["dmg", "pkg", "iso"]

        for source in sources {
            try Task.checkCancellation()
            let rootURL = URL(fileURLWithPath: source.dir)
            guard fm.fileExists(atPath: source.dir), !safetyManager.isSymlinkDirectory(rootURL) else { continue }
            let entries = (try? fm.contentsOfDirectory(atPath: source.dir)) ?? []
            for name in entries {
                try Task.checkCancellation()
                // Extension check before stat/attributesOfItem so messenger media dirs stay fast.
                let ext = (name as NSString).pathExtension.lowercased()
                let isImage = imageExtensions.contains(ext)
                let isZipCandidate = source.allowInstallerZip && ext == "zip"
                guard isImage || isZipCandidate else { continue }

                let path = "\(source.dir)/\(name)"
                guard seenPaths.insert(NormalizedPath.key(URL(fileURLWithPath: path))).inserted else { continue }

                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int64 else {
                    skipped += 1
                    continue
                }

                let minRequired = isZipCandidate ? ZipCentralDirectoryInspector.minimumInstallerZipBytes + 1 : minImageSize
                guard size >= minRequired else {
                    skipped += 1
                    continue
                }

                let modified = attrs[.modificationDate] as? Date
                let isOld = (modified ?? .distantPast) < cutoff
                let isVeryLarge = size >= 200 * 1024 * 1024
                guard isOld || isVeryLarge else {
                    skipped += 1
                    continue
                }

                if isZipCandidate && !ZipCentralDirectoryInspector.containsInstallerPayload(at: path, fileSize: size) {
                    skipped += 1
                    continue
                }

                let alreadyInstalled = Self.installerMatchesInstalledApp(fileName: name, installedStems: installedApps)
                let description = alreadyInstalled
                    ? String(format: "cleanup_installer_desc_installed_format".localized, source.sourceName)
                    : String(format: "cleanup_installer_desc_source_format".localized, source.sourceName)

                found += 1
                totalBytes += size
                progress?(.fileItem(
                    path: path,
                    sizeBytes: size,
                    modificationDate: modified,
                    isDirectory: false,
                    category: label,
                    parentName: label,
                    isSelected: false,
                    description: description
                ))
                progress?(.log("  review: \(shortPath(path)) — \(Self.formatBytes(size)) (opt-in)"))
            }
        }

        let mb = Int(totalBytes / (1024 * 1024))
        progress?(.log("Installer Packages: found=\(found) skipped=\(skipped) — select explicitly; engine does not delete"))
        progress?(.result(label: label, freedMB: dryRun ? mb : 0))
        return [CleanupEngineResult(
            label: label,
            freedMB: dryRun ? mb : 0,
            freedBytes: dryRun ? totalBytes : 0,
            removedCount: 0,
            skippedCount: skipped,
            failedCount: 0
        )]
    }

    static func installedApplicationStemNames(home: String, fileManager: FileManager = .default) -> Set<String> {
        var stems = Set<String>()
        for dir in ["/Applications", "\(home)/Applications"] {
            guard let items = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.lowercased().hasSuffix(".app") {
                let raw = String(item.dropLast(4))
                let normalized = normalizeInstallerToken(raw)
                if normalized.count >= 3 {
                    stems.insert(normalized)
                }
            }
        }
        return stems
    }

    static func installerMatchesInstalledApp(fileName: String, installedStems: Set<String>) -> Bool {
        guard !installedStems.isEmpty else { return false }
        var stem = (fileName as NSString).deletingPathExtension
        // Strip Homebrew download sha256 prefix `<64-hex>--`.
        if let range = stem.range(of: #"^[0-9a-fA-F]{64}--"#, options: .regularExpression) {
            stem.removeSubrange(range)
        }
        let normalized = normalizeInstallerToken(stem)
        guard !normalized.isEmpty else { return false }
        if installedStems.contains(normalized) {
            return true
        }
        return installedStems.contains { appStem in
            appStem.count >= 4 && normalized.hasPrefix(appStem)
        }
    }

    private static func normalizeInstallerToken(_ raw: String) -> String {
        var s = raw.lowercased()
        // Strip common trailing version/arch/platform tokens before normalizing alphanumerics.
        let suffixes = ["universal", "arm64", "x86_64", "x64", "macos", "osx", "mac", "darwin", "installer", "setup"]
        for suffix in suffixes {
            s = s.replacingOccurrences(of: "-\(suffix)", with: "")
            s = s.replacingOccurrences(of: "_\(suffix)", with: "")
            s = s.replacingOccurrences(of: " \(suffix)", with: "")
        }
        if let verRange = s.range(of: #"[-_ ]v?\d+(?:\.\d+)*(?:\s*\(\d+\))?$"#, options: .regularExpression) {
            s.removeSubrange(verRange)
        }
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    // MARK: 50. DNS Flush

    func cleanDNSFlush(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Flushing DNS cache..."))
        if dryRun {
            progress?(.log("  Would run: dscacheutil -flushcache && killall -HUP mDNSResponder"))
            emitFileItem(CleanupFileItem(path: "command://dns/flush", sizeBytes: 0, modificationDate: nil, isDirectory: false), category: "DNS Cache", parentName: nil, isSelected: false, isCommandBacked: true, progress: progress)
            progress?(.result(label: "DNS Cache", freedMB: 0))
            return [CleanupEngineResult(label: "DNS Cache", freedMB: 0)]
        }
        if skipsUnselected("command://dns/flush", dryRun: dryRun) {
            return [CleanupEngineResult(label: "DNS Cache", freedMB: 0, skippedCount: 1)]
        }
        do {
            try Task.checkCancellation()
            let flushResult = try await commandRunner.run(command: "/usr/bin/dscacheutil", arguments: ["-flushcache"])
            if flushResult.exitCode == 0 {
                progress?(.log("  ✓ DNS cache flushed successfully"))
            } else {
                progress?(.log("  DNS cache flush requires elevated privileges"))
            }
        } catch {
            progress?(.log("  ✗ DNS cache flush failed: \(error.localizedDescription)"))
        }
        progress?(.result(label: "DNS Cache", freedMB: 0))
        return [CleanupEngineResult(label: "DNS Cache", freedMB: 0)]
    }

    // MARK: 50. Font Cache

    func cleanFontCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Clearing font cache..."))
        if dryRun {
            progress?(.log("  Would run: sudo atsutil databases -remove"))
            progress?(.log("  Requires restart to take effect"))
            emitFileItem(CleanupFileItem(path: "command://font/cache-clear", sizeBytes: 0, modificationDate: nil, isDirectory: false), category: "Font Cache", parentName: nil, isSelected: false, isCommandBacked: true, progress: progress)
            progress?(.result(label: "Font Cache", freedMB: 0))
            return [CleanupEngineResult(label: "Font Cache", freedMB: 0)]
        }
        if skipsUnselected("command://font/cache-clear", dryRun: dryRun) {
            return [CleanupEngineResult(label: "Font Cache", freedMB: 0, skippedCount: 1)]
        }
        do {
            let result = try await commandRunner.run(command: "/usr/bin/atsutil", arguments: ["databases", "-remove"])
            if result.exitCode == 0 {
                progress?(.log("  Font cache cleared — restart required"))
            } else {
                progress?(.log("  Font cache clear requires administrator privileges"))
            }
        } catch {
            progress?(.log("  Font cache clear failed: \(error.localizedDescription)"))
        }
        progress?(.result(label: "Font Cache", freedMB: 0))
        return [CleanupEngineResult(label: "Font Cache", freedMB: 0)]
    }
}


