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
    case fileItem(path: String, sizeBytes: Int64, modificationDate: Date?, isDirectory: Bool, category: String, parentName: String?)
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

    /// True when at least one path failed — must not be treated as full success.
    public var isPartialFailure: Bool { failedCount > 0 }
    public var isSuccess: Bool { failedCount == 0 }

    public init(
        label: String,
        freedMB: Int,
        freedBytes: Int64? = nil,
        removedCount: Int = 0,
        skippedCount: Int = 0,
        failedCount: Int = 0
    ) {
        self.label = label
        self.freedMB = freedMB
        self.freedBytes = freedBytes ?? Int64(freedMB) * 1024 * 1024
        self.removedCount = removedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
    }
}

// MARK: - Cleanup Category

/// Cleanup categories corresponding to shell script steps.
public enum CleanupCategory: String, CaseIterable, Sendable {
    case appCaches = "app_caches"
    case packageManagers = "package_managers"
    case gradleMaven = "gradle_maven"
    case flutterDart = "flutter_dart"
    case xcode = "xcode"
    case iosSimulators = "ios_simulators"
    case androidCaches = "android_caches"
    case androidSDK = "android_sdk"
    case ideCaches = "ide_caches"
    case browserCaches = "browser_caches"
    case messagingMedia = "messaging_media"
    case docker = "docker"
    case languageCaches = "language_caches"
    case userLogs = "user_logs"
    case systemCaches = "system_caches"
    case appContainers = "app_containers"
    case dotfileCaches = "dotfile_caches"
    case scatteredJunk = "scattered_junk"
    case orphanedRemnants = "orphaned_remnants"
    case orphanedFiles = "orphaned_files"
    case largeFiles = "large_files"
    case dynamicCacheDiscovery = "dynamic_cache_discovery"
    
    // New categories
    case timeMachineSnapshots = "time_machine_snapshots"
    case iosBackups = "ios_backups"
    case mailDownloads = "mail_downloads"
    case savedAppState = "saved_app_state"
    case crashReporter = "crash_reporter"
    case assetsV2 = "assets_v2"
    case cloudKitCache = "cloud_kit_cache"
    case swiftPMCache = "swift_pm_cache"
    case carthageCache = "carthage_cache"
    case steamCache = "steam_cache"
    case teamsCache = "teams_cache"
    case adobeCaches = "adobe_caches"
    case chromeExtraCaches = "chrome_extra_caches"
    case ideOldVersions = "ide_old_versions"

    // Phase 3: New categories from fixtures
    case launchAgents = "launch_agents"
    case launchDaemons = "launch_daemons"
    case privilegedHelpers = "privileged_helpers"
    case pkgReceipts = "pkg_receipts"
    case internetPlugins = "internet_plugins"
    case sharedFileLists = "shared_file_lists"
    case cloudDocs = "cloud_docs"

    // Phase 3: New categories from cleanup.json
    case photosCache = "photos_cache"
    case voiceMemos = "voice_memos"
    case garageBandLogic = "garage_band_logic"
    case iMovieFinalCut = "imovie_final_cut"
    case garminFitbit = "garmin_fitbit"
    case oldBackups = "old_backups"
    case aiModels = "ai_models"
    case installerPackages = "installer_packages"
    case dnsFlush = "dns_flush"
    case fontCache = "font_cache"
    case sleepImage = "sleep_image"
    case duplicateFiles = "duplicate_files"
    case unusedApps = "unused_apps"
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
    let scanActor: ScanActor
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
        self.sizeCache = DirectorySizeCache()
        self.fileActor = FileCleanupActor(
            safetyManager: safety,
            sizeCache: DirectorySizeCache(),
            fileSystemContext: fileSystemContext
        )
        self.processActor = ProcessCleanupActor(commandRunner: commandRunner)
        self.scanActor = ScanActor()
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

        let maxConcurrency = dryRun ? ProcessInfo.processInfo.activeProcessorCount : 1

        var pending = Array(categories.enumerated())
        var completedCount = 0

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

    private func runCategoryWithTimeout(
        _ category: CleanupCategory,
        dryRun: Bool,
        options: CleanupOptions,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?
    ) async -> [CleanupEngineResult] {
        let timeout = Self.timeoutForCategory(category)
        let title = Self.titleForCategory(category)
        do {
            return try await withTimeout(timeout) {
                try await self.runCategory(category, dryRun: dryRun, options: options, progress: progress)
            }
        } catch is CancellationError {
            progress?(.log("⚠️ \(title) — cancelled"))
            return []
        } catch {
            let isTimeout = (error as? CleanupEngineError) == .timeout
            let reason = isTimeout ? "timed out after \(Int(timeout.components.seconds))s" : error.localizedDescription
            progress?(.log("⚠️ \(title) — \(reason), skipped"))
            Logger.engine.warning("Category \(title) failed: \(reason)")
            return []
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
        case .flutterDart: return try await cleanFlutterDart(dryRun: dryRun, progress: progress, cleanProjects: options.cleanProjects)
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
        case .orphanedRemnants: return try await cleanOrphanedRemnants(dryRun: dryRun, progress: progress)
        case .orphanedFiles: return try await cleanOrphanedFiles(dryRun: dryRun, progress: progress)
        case .largeFiles: return try await cleanLargeFiles(dryRun: dryRun, progress: progress)
        case .dynamicCacheDiscovery: return try await cleanDynamicCacheDiscovery(dryRun: dryRun, progress: progress)
        case .timeMachineSnapshots: return try await cleanTimeMachineSnapshots(dryRun: dryRun, progress: progress)
        case .iosBackups: return try await cleanIOSBackups(dryRun: dryRun, progress: progress)
        case .mailDownloads: return try await cleanMailDownloads(dryRun: dryRun, progress: progress)
        case .savedAppState: return try await cleanSavedAppState(dryRun: dryRun, progress: progress)
        case .crashReporter: return try await cleanCrashReporter(dryRun: dryRun, progress: progress)
        case .ideOldVersions: return try await cleanIDEOldVersions(dryRun: dryRun, progress: progress)
        case .assetsV2: return try await cleanAssetsV2(dryRun: dryRun, progress: progress)
        case .cloudKitCache: return try await cleanCloudKitCache(dryRun: dryRun, progress: progress)
        case .swiftPMCache: return try await cleanSwiftPMCache(dryRun: dryRun, progress: progress)
        case .carthageCache: return try await cleanCarthageCache(dryRun: dryRun, progress: progress)
        case .steamCache: return try await cleanSteamCache(dryRun: dryRun, progress: progress)
        case .teamsCache: return try await cleanTeamsCache(dryRun: dryRun, progress: progress)
        case .adobeCaches: return try await cleanAdobeCaches(dryRun: dryRun, progress: progress)
        case .chromeExtraCaches: return try await cleanChromeExtraCaches(dryRun: dryRun, progress: progress)
        case .launchAgents: return try await cleanLaunchAgents(dryRun: dryRun, progress: progress)
        case .launchDaemons: return try await cleanLaunchDaemons(dryRun: dryRun, progress: progress)
        case .privilegedHelpers: return try await cleanPrivilegedHelpers(dryRun: dryRun, progress: progress)
        case .pkgReceipts: return try await cleanPkgReceipts(dryRun: dryRun, progress: progress)
        case .internetPlugins: return try await cleanInternetPlugins(dryRun: dryRun, progress: progress)
        case .sharedFileLists: return try await cleanSharedFileLists(dryRun: dryRun, progress: progress)
        case .cloudDocs: return try await cleanCloudDocs(dryRun: dryRun, progress: progress)
        case .photosCache: return try await cleanPhotosCache(dryRun: dryRun, progress: progress)
        case .voiceMemos: return try await cleanVoiceMemos(dryRun: dryRun, progress: progress)
        case .garageBandLogic: return try await cleanGarageBandLogic(dryRun: dryRun, progress: progress)
        case .iMovieFinalCut: return try await cleanIMovieFinalCut(dryRun: dryRun, progress: progress)
        case .garminFitbit: return try await cleanGarminFitbit(dryRun: dryRun, progress: progress)
        case .oldBackups: return try await cleanOldBackups(dryRun: dryRun, progress: progress)
        case .aiModels: return try await cleanAIModels(dryRun: dryRun, progress: progress)
        case .installerPackages: return try await cleanInstallerPackages(dryRun: dryRun, progress: progress)
        case .dnsFlush: return try await cleanDNSFlush(dryRun: dryRun, progress: progress)
        case .fontCache: return try await cleanFontCache(dryRun: dryRun, progress: progress)
        case .sleepImage: return try await cleanSleepImage(dryRun: dryRun, progress: progress)
        case .duplicateFiles: return try await cleanDuplicateFiles(dryRun: dryRun, progress: progress)
        case .unusedApps: return try await cleanUnusedApps(dryRun: dryRun, progress: progress)
        }
    }

    private static func timeoutForCategory(_ category: CleanupCategory) -> Duration {
        switch category {
        case .packageManagers, .docker, .languageCaches, .androidSDK, .timeMachineSnapshots, .ideOldVersions, .userLogs:
            return .seconds(120)
        case .xcode, .iosSimulators, .appCaches, .ideCaches, .flutterDart, .systemCaches, .androidCaches, .gradleMaven, .dotfileCaches, .browserCaches, .chromeExtraCaches, .steamCache, .teamsCache, .adobeCaches, .cloudKitCache, .swiftPMCache, .carthageCache, .photosCache:
            return .seconds(300)
        case .scatteredJunk:
            return .seconds(600)
        case .orphanedRemnants, .appContainers, .dynamicCacheDiscovery, .largeFiles, .orphanedFiles:
            return .seconds(300)
        case .launchDaemons, .privilegedHelpers, .sleepImage, .duplicateFiles:
            return .seconds(120)
        default:
            return .seconds(60)
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

    private func withTimeout<T: Sendable>(_ duration: Duration, operation: @Sendable @escaping () async throws -> T) async throws -> T {
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
    /// When true, includes .DS_Store and other scattered junk files.
    public var cleanDSStore: Bool = false
    /// When true, cleans Maven local repository (~/.m2/repository).
    public var cleanMaven: Bool = true
    /// When true, cleans Go module cache (GOMODCACHE).
    public var cleanModCache: Bool = true
    /// When true, deep cleans project artifacts (.dart_tool directories).
    public var cleanProjects: Bool = true
    /// Xcode Archives older than this many days will be cleaned.
    public var xcodeArchivesOlderThanDays: Int = 90
    /// When true, cleans CloudDocs (iCloud document cache).
    public var cleanCloudDocs: Bool = false
    /// When true, cleans Voice Memos recordings.
    public var cleanVoiceMemos: Bool = false
    /// When true, cleans GarageBand / Logic Pro projects.
    public var cleanGarageBandLogic: Bool = false
    /// When true, cleans iMovie / Final Cut render files.
    public var cleanIMovieFinalCut: Bool = false
    /// When true, removes sleep image (disables hibernation).
    public var cleanSleepImage: Bool = false
    /// When true, cleans Time Machine local snapshots.
    public var cleanTimeMachineSnapshots: Bool = false

    public init(cleanDSStore: Bool = false, cleanMaven: Bool = true, cleanModCache: Bool = true, cleanProjects: Bool = true, xcodeArchivesOlderThanDays: Int = 90, cleanCloudDocs: Bool = false, cleanVoiceMemos: Bool = false, cleanGarageBandLogic: Bool = false, cleanIMovieFinalCut: Bool = false, cleanSleepImage: Bool = false, cleanTimeMachineSnapshots: Bool = false) {
        self.cleanDSStore = cleanDSStore
        self.cleanMaven = cleanMaven
        self.cleanModCache = cleanModCache
        self.cleanProjects = cleanProjects
        self.xcodeArchivesOlderThanDays = xcodeArchivesOlderThanDays
        self.cleanCloudDocs = cleanCloudDocs
        self.cleanVoiceMemos = cleanVoiceMemos
        self.cleanGarageBandLogic = cleanGarageBandLogic
        self.cleanIMovieFinalCut = cleanIMovieFinalCut
        self.cleanSleepImage = cleanSleepImage
        self.cleanTimeMachineSnapshots = cleanTimeMachineSnapshots
    }

    /// Returns ALL categories for scanning (like the shell script always does).
    public func scanCategories() -> [CleanupCategory] {
        return CleanupCategory.allCases
    }

    /// Returns the set of categories to actually clean based on these options.
    ///
    /// Dangerous categories are excluded from automatic cleanup until they have
    /// per-item ownership proofs and explicit user selection:
    /// orphaned remnants/files, old backups, AI/LLM user_content, installer packages,
    /// large-file review items, launch agents/daemons,
    /// privileged helpers, package receipts, internet plugins.
    public func categories() -> [CleanupCategory] {
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
            .iosBackups,
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
            .ideOldVersions,
            .sharedFileLists,
            .photosCache,
            .garminFitbit,
            .dnsFlush,
            .fontCache,
            .duplicateFiles,
            .unusedApps,
        ]

        if cleanDSStore {
            categories.append(.scatteredJunk)
        }
        if cleanCloudDocs {
            categories.append(.cloudDocs)
        }
        if cleanVoiceMemos {
            categories.append(.voiceMemos)
        }
        if cleanTimeMachineSnapshots {
            categories.append(.timeMachineSnapshots)
        }
        if cleanGarageBandLogic {
            categories.append(.garageBandLogic)
        }
        if cleanIMovieFinalCut {
            categories.append(.iMovieFinalCut)
        }
        if cleanSleepImage {
            categories.append(.sleepImage)
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

// MARK: - FileManager Helpers

extension CleanupEngine {

    func emitFileItem(_ item: CleanupFileItem?, category: String, parentName: String?, progress: (@Sendable (CleanupEngineEvent) -> Void)?) {
        guard let item else { return }
        progress?(.fileItem(
            path: item.path,
            sizeBytes: item.sizeBytes,
            modificationDate: item.modificationDate,
            isDirectory: item.isDirectory,
            category: category,
            parentName: parentName
        ))
    }

    func cleanContents(of path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        try await fileActor.cleanContents(of: path, dryRun: dryRun, progress: progress)
    }

    func removeDirectory(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        try await fileActor.removeDirectory(path, dryRun: dryRun, progress: progress)
    }

    func removeFile(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        try await fileActor.removeFile(path, dryRun: dryRun, progress: progress)
    }

    func getDirectorySize(_ path: String) async -> Int64 {
        await fileActor.getDirectorySize(path)
    }

    func cleanOldFiles(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        try await fileActor.cleanOldFiles(in: path, olderThanDays: days, dryRun: dryRun, progress: progress)
    }

    func cleanOldFilesRecursive(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> (freed: Int64, item: CleanupFileItem?) {
        try await fileActor.cleanOldFilesRecursive(in: path, olderThanDays: days, dryRun: dryRun, progress: progress)
    }

    func cleanContentsParallel(_ paths: [String], dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) async throws -> Int64 {
        try await fileActor.cleanContentsParallel(paths, dryRun: dryRun, progress: progress)
    }

    /// Absolute existing paths from EmbeddedCleanupPaths (+ GeneratedCleanupPaths merge).
    func resolvedEmbeddedPaths(for category: CleanupCategory) -> [String] {
        let home = fileSystemContext.homePath
        var result: [String] = []
        var seen = Set<String>()
        for entry in EmbeddedCleanupPaths.paths(for: category) {
            for path in CleanupPathExpander.expand(entry.path, home: home, fileManager: fm) {
                if seen.insert(path).inserted {
                    result.append(path)
                }
            }
        }
        return result
    }

    func cleanFromEmbeddedPaths(
        _ category: CleanupCategory,
        label: String,
        dryRun: Bool,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?
    ) async throws -> [CleanupEngineResult] {
        // EmbeddedCleanupPaths merges only GeneratedCleanupPaths.cachePaths —
        // shared / app_data / user_content never enter this executor.
        let paths = resolvedEmbeddedPaths(for: category)
        progress?(.log("Scanning \(label) (\(paths.count) paths)..."))
        var totalFreed: Int64 = 0
        var removed = 0
        var skipped = 0
        var failed = 0
        for path in paths {
            try Task.checkCancellation()
            do {
                let (freed, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
                if freed > 0 || item != nil {
                    removed += 1
                    totalFreed += freed
                } else {
                    skipped += 1
                }
                if dryRun { emitFileItem(item, category: label, parentName: nil, progress: progress) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed += 1
                progress?(.log("  \(shortPath(path)) — failed: \(error.localizedDescription)"))
            }
        }
        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("\(label): removed=\(removed) skipped=\(skipped) failed=\(failed) total=\(Self.formatBytes(totalFreed))"))
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
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("brew --cache 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheDir = cachePath ?? "\(home)/Library/Caches/Homebrew"
            progress?(.log("  Cache path: \(shortPath(cacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  Homebrew cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "Homebrew cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = await getDirectorySize(cacheDir)
                progress?(.log("  Running: brew cleanup --prune=all -q"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("brew cleanup --prune=all -q")])
                let after = await getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.log("  Homebrew: freed \(Self.formatBytes(max(0, before - after)))"))
                progress?(.result(label: "Homebrew cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: freed))
            }
        } else {
            progress?(.log("  Homebrew not found, skipped"))
        }

        // npm
        if await commandRunner.commandExists("npm") {
            progress?(.log("  npm detected"))
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("npm config get cache 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheDir = cachePath ?? "\(home)/.npm"
            progress?(.log("  Cache path: \(shortPath(cacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  npm cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "npm cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = await getDirectorySize(cacheDir)
                progress?(.log("  Running: npm cache clean --force"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("npm cache clean --force 2>/dev/null")])
                let after = await getDirectorySize(cacheDir)
                var freed = Int(max(0, before - after) / (1024 * 1024))
                // Fallback: manual cleanup if npm didn't free space
                if freed == 0 && before > 0 {
                    progress?(.log("  npm cache clean didn't free space, trying manual cleanup..."))
                    _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("find \"\(cacheDir)\" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true")])
                    let after2 = await getDirectorySize(cacheDir)
                    freed = Int(max(0, before - after2) / (1024 * 1024))
                }
                progress?(.log("  npm: freed \(Self.formatBytes(max(0, before - after)))"))
                progress?(.result(label: "npm cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: freed))
            }
        } else {
            progress?(.log("  npm not found, skipped"))
        }

        // yarn
        if await commandRunner.commandExists("yarn") {
            progress?(.log("  yarn detected"))
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("yarn cache dir 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheDir = cachePath ?? "\(home)/Library/Caches/Yarn"
            progress?(.log("  Cache path: \(shortPath(cacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  yarn cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "yarn cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "yarn cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = await getDirectorySize(cacheDir)
                progress?(.log("  Running: yarn cache clean"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("yarn cache clean 2>/dev/null")])
                let after = await getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.log("  yarn: freed \(Self.formatBytes(max(0, before - after)))"))
                progress?(.result(label: "yarn cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "yarn cache", freedMB: freed))
            }
        } else {
            progress?(.log("  yarn not found, skipped"))
        }

        // pnpm
        if await commandRunner.commandExists("pnpm") {
            progress?(.log("  pnpm detected"))
            let storePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("pnpm store path 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let storeDir = storePath ?? "\(home)/Library/pnpm/store"
            progress?(.log("  Store path: \(shortPath(storeDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(storeDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  pnpm store: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "pnpm store", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "pnpm store", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: storeDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
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
        } else {
            progress?(.log("  pnpm not found, skipped"))
        }

        // CocoaPods
        if await commandRunner.commandExists("pod") {
            progress?(.log("  CocoaPods detected"))
            let cacheDir = "\(home)/Library/Caches/CocoaPods"
            progress?(.log("  Cache path: \(shortPath(cacheDir))"))

            if dryRun {
                let sizeBytes = await getDirectorySize(cacheDir)
                let sizeMB = Int(sizeBytes / (1024 * 1024))
                progress?(.log("  CocoaPods cache: \(Self.formatBytes(sizeBytes))"))
                progress?(.result(label: "CocoaPods cache", freedMB: sizeMB))
                results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: sizeMB))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: sizeBytes, modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = await getDirectorySize(cacheDir)
                progress?(.log("  Running: pod cache clean --all"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("pod cache clean --all 2>/dev/null")])
                let after = await getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.log("  CocoaPods: freed \(Self.formatBytes(max(0, before - after)))"))
                progress?(.result(label: "CocoaPods cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: freed))
            }
        } else {
            progress?(.log("  CocoaPods not found, skipped"))
        }

        return results
    }

    // MARK: 3. Gradle + Maven

    func cleanGradleMaven(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?, cleanMaven: Bool = false) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Gradle + Maven caches..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/.gradle/caches",
            "\(home)/.gradle/wrapper/dists",
            "\(home)/.gradle/daemon",
            "\(home)/.gradle/buildOutputCleanup",
            "\(home)/.kotlin",
        ]
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

    func cleanFlutterDart(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?, cleanProjects: Bool = false) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Flutter / Dart caches..."))
        var freed: Int64 = 0

        let dirs = [
            "\(home)/.pub-cache/hosted",
            "\(home)/.pub-cache/git",
            "\(home)/.dartServer",
            "\(home)/.flutter-devtools"
        ]
        for path in dirs {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Flutter / Dart", parentName: nil, progress: progress) }
        }

        // .dart_tool in projects — OPT-IN only
        if cleanProjects {
            progress?(.log("  Scanning for .dart_tool directories..."))
            let projectBases = [
                "\(home)/Documents",
                "\(home)/Projects",
                "\(home)/Developer",
                "\(home)/dev",
                "\(home)/code",
                "\(home)/repos"
            ]
            for base in projectBases {
                guard fm.fileExists(atPath: base) else { continue }
                if let enumerator = fm.enumerator(atPath: base) {
                    while let item = enumerator.nextObject() as? String {
                        let fullPath = "\(base)/\(item)"
                        // Skip heavy directories (Docker, VMs)
                        if Self.isHeavyDirectory(fullPath) {
                            enumerator.skipDescendants()
                            continue
                        }
                        if item == ".dart_tool" {
                            let (f, item) = try await cleanContents(of: fullPath, dryRun: dryRun, progress: progress)
                            freed += f
                            if dryRun { emitFileItem(item, category: "Flutter / Dart", parentName: ".dart_tool", progress: progress) }
                            enumerator.skipDescendants()
                        } else if (fullPath as NSString).pathComponents.count - (base as NSString).pathComponents.count > 5 {
                            enumerator.skipDescendants()
                        }
                    }
                }
            }
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

        // Project-local build artifacts (DerivedData, build/ inside project repos)
        let projectLocalFreed = try await cleanProjectLocalBuildArtifacts(home: home, dryRun: dryRun, progress: progress)
        freed += projectLocalFreed

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Xcode total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Xcode cleanup", freedMB: mb))
        return [CleanupEngineResult(label: "Xcode", freedMB: mb)]
    }

    /// Scans common developer directories for project-local build artifacts.
    /// All targets are 100% regenerable by their respective build tools.
    private func cleanProjectLocalBuildArtifacts(
        home: String,
        dryRun: Bool,
        progress: (@Sendable (CleanupEngineEvent) -> Void)?
    ) async throws -> Int64 {
        let searchRoots = [
            "\(home)/Documents",
            "\(home)/Developer",
            "\(home)/Projects",
            "\(home)/repos",
            "\(home)/src",
            "\(home)/Desktop",
            "\(home)/workspace",
            "\(home)/code",
        ]

        // Directories always safe to remove (no sibling check needed)
        let alwaysRemovable: Set<String> = [
            "DerivedData",          // Xcode
            ".dart_tool",           // Dart/Flutter
            "__pycache__",          // Python
            ".pytest_cache",        // Python pytest
            ".mypy_cache",          // Python mypy
            ".ruff_cache",          // Python ruff
            ".tox",                 // Python tox
            ".next",                // Next.js
            ".nuxt",                // Nuxt.js
            ".turbo",              // Turborepo
            ".parcel-cache",        // Parcel
            ".angular",             // Angular CLI
            ".svelte-kit",          // SvelteKit
        ]

        // Directories that need sibling file verification
        // (dirName -> [required sibling files])
        let conditionalRemovable: [(name: String, siblings: [String])] = [
            // Xcode / Swift
            (name: ".build", siblings: ["Package.swift", "project.yml"]),
            (name: "build", siblings: [".xcodeproj", ".xcworkspace", "Package.swift", "project.yml",
                                       "build.gradle", "build.gradle.kts", "CMakeLists.txt", "Makefile",
                                       "pubspec.yaml"]),
            // Android / Gradle
            (name: ".gradle", siblings: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]),
            // Flutter
            (name: ".flutter-plugins", siblings: ["pubspec.yaml"]),
            (name: ".flutter-plugins-dependencies", siblings: ["pubspec.yaml"]),
            // Node.js
            (name: "node_modules", siblings: ["package.json"]),
            (name: "dist", siblings: ["package.json", "tsconfig.json", "vite.config.ts", "vite.config.js",
                                      "webpack.config.js", "rollup.config.js"]),
            // Rust
            (name: "target", siblings: ["Cargo.toml"]),
            // Go
            (name: "vendor", siblings: ["go.mod"]),
            // Python virtualenvs
            (name: "venv", siblings: ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"]),
            (name: ".venv", siblings: ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"]),
            (name: ".eggs", siblings: ["setup.py", "pyproject.toml"]),
            // CMake
            (name: "CMakeFiles", siblings: ["CMakeLists.txt", "CMakeCache.txt"]),
        ]

        let maxDepth = 5
        var freed: Int64 = 0
        var foundCount = 0

        // Pre-build lookup sets
        let conditionalNames = Set(conditionalRemovable.map(\.name))
        let skipDescent: Set<String> = [".git", ".svn", ".hg", "Pods", ".cocoapods"]

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

                // Skip VCS and heavy non-artifact dirs
                if skipDescent.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }

                // Check if this is an always-removable artifact
                if alwaysRemovable.contains(name) {
                    enumerator.skipDescendants()
                    do {
                        let (f, item) = try await removeDirectory(url.path, dryRun: dryRun, progress: progress)
                        freed += f
                        foundCount += 1
                        if dryRun { emitFileItem(item, category: "Xcode", parentName: "Project build artifacts", progress: progress) }
                    } catch is SafetyError {
                        progress?(.log("  \(shortPath(url.path)) — protected, skipped"))
                    }
                    continue
                }

                // Check conditional removable (needs sibling verification)
                guard conditionalNames.contains(name) else { continue }

                let parent = url.deletingLastPathComponent()
                let siblings = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []

                var matched = false
                for rule in conditionalRemovable where rule.name == name {
                    for required in rule.siblings {
                        if required.hasPrefix(".") && required.contains("proj") || required.contains("workspace") {
                            // Suffix match for .xcodeproj, .xcworkspace
                            if siblings.contains(where: { $0.hasSuffix(required) }) { matched = true; break }
                        } else {
                            if siblings.contains(required) { matched = true; break }
                        }
                    }
                    if matched { break }
                }

                guard matched else { continue }

                enumerator.skipDescendants()
                do {
                    let (f, item) = try await removeDirectory(url.path, dryRun: dryRun, progress: progress)
                    freed += f
                    foundCount += 1
                    if dryRun { emitFileItem(item, category: "Xcode", parentName: "Project build artifacts", progress: progress) }
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
        if dryRun { emitFileItem(ci, category: "iOS Simulators", parentName: nil, progress: progress) }

        if await commandRunner.commandExists("xcrun") {
            let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl list devices 2>/dev/null | grep -c 'unavailable' || echo 0"])
            let count = Int(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
            progress?(.log("  Unavailable simulator devices: \(count)"))

            if !dryRun && count > 0 {
                progress?(.log("  Running: xcrun simctl delete unavailable"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl delete unavailable 2>/dev/null"])
                progress?(.log("  Deleted \(count) unavailable devices"))
            }

            // Old iOS runtime cleanup: keep only latest stable
            let runtimesResult = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl list runtimes 2>/dev/null | grep '^iOS' | awk '{print $NF}' | sort -V"])
            if let output = runtimesResult?.stdout {
                let runtimeIDs = output.split(separator: "\n").map { String($0) }
                progress?(.log("  Found \(runtimeIDs.count) iOS runtimes"))
                
                if runtimeIDs.count > 1 {
                    // Find latest stable (no rc/beta/alpha/preview)
                    let stableRuntimes = runtimeIDs.filter { !$0.lowercased().contains("rc") && !$0.lowercased().contains("beta") && !$0.lowercased().contains("alpha") && !$0.lowercased().contains("preview") }
                    let sortedStable = stableRuntimes.sorted { ($0 as NSString).compare($1, options: .numeric) == .orderedAscending }
                    let keepRuntime = stableRuntimes.isEmpty ? runtimeIDs.last! : sortedStable.last!
                    
                    let cryptexPath = "\(home)/Library/Developer/CoreSimulator/Cryptex"
                    let beforeSize = await getDirectorySize(cryptexPath)
                    
                    for runtime in runtimeIDs {
                        if runtime == keepRuntime { continue }
                        if dryRun {
                            progress?(.log("  ⊘ Would delete iOS runtime: \(runtime)"))
                        } else {
                            progress?(.log("  Deleting iOS runtime: \(runtime)"))
                            _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl runtime delete \(runtime) 2>/dev/null"])
                        }
                    }
                    
                    if !dryRun {
                        let afterSize = await getDirectorySize(cryptexPath)
                        let rtFreed = max(0, beforeSize - afterSize)
                        freed += rtFreed
                        progress?(.log("  iOS runtimes freed: \(Self.formatBytes(rtFreed))"))
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
            // Filter out non-device entries (.DS_Store, device_set.plist)
            let devices = allEntries.filter { entry in
                !entry.hasPrefix(".") && entry != "device_set.plist" && entry.contains("-")
            }
            let deviceCount = devices.count
            progress?(.log("  Found \(deviceCount) simulator devices"))
            for device in devices {
                let cachesPath = "\(devicesPath)/\(device)/data/Library/Caches"
                let tmpPath = "\(devicesPath)/\(device)/data/tmp"
                let (f1, i1) = try await cleanContents(of: cachesPath, dryRun: dryRun, progress: progress)
                freed += f1
                if dryRun { emitFileItem(i1, category: "iOS Simulators", parentName: nil, progress: progress) }
                let (f2, i2) = try await cleanContents(of: tmpPath, dryRun: dryRun, progress: progress)
                freed += f2
                if dryRun { emitFileItem(i2, category: "iOS Simulators", parentName: nil, progress: progress) }
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

        let paths = [
            "\(home)/.android/cache",
            "\(home)/.android/build-cache",
            "\(home)/Library/Android/sdk/.temp"
        ]
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

        // Find sdkmanager
        var sdkmanager: String?
        let candidates = [
            "\(sdkPath)/cmdline-tools/latest/bin/sdkmanager",
            "\(sdkPath)/tools/bin/sdkmanager"
        ]
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                sdkmanager = path
                progress?(.log("  sdkmanager found at \(shortPath(path))"))
                break
            }
        }
        if sdkmanager == nil {
            progress?(.log("  sdkmanager not found"))
        }

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
                if dryRun { emitFileItem(item, category: "Android SDK", parentName: nil, progress: progress) }
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
                if dryRun { emitFileItem(item, category: "Android SDK", parentName: nil, progress: progress) }
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
            let (freed, item) = try await cleanContents(of: dir, dryRun: dryRun, progress: progress)
            totalFreed += freed
            if dryRun { emitFileItem(item, category: "IDE / Electron caches", parentName: nil, progress: progress) }
        }

        // Dynamic discovery: unknown Electron apps — Cache / Code Cache / GPUCache / CachedData
        let electronLeaves = ["Cache", "Code Cache", "GPUCache", "CachedData"]
        let appSupportPath = "\(home)/Library/Application Support"
        if fm.fileExists(atPath: appSupportPath) {
            let apps = (try? fm.contentsOfDirectory(atPath: appSupportPath)) ?? []
            for appDir in apps {
                try Task.checkCancellation()
                guard !knownApps.contains(appDir) else { continue }
                for leaf in electronLeaves {
                    let cachePath = "\(appSupportPath)/\(appDir)/\(leaf)"
                    guard fm.fileExists(atPath: cachePath) else { continue }
                    let size = await getDirectorySize(cachePath)
                    guard size >= 5 * 1024 * 1024 else { continue } // skip < 5 MB
                    let (freed, item) = try await cleanContents(of: cachePath, dryRun: dryRun, progress: progress)
                    totalFreed += freed
                    if dryRun {
                        emitFileItem(item, category: "IDE / Electron caches", parentName: "\(appDir)/\(leaf)", progress: progress)
                    }
                }
            }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("IDE / Electron total: \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: "IDE / Electron caches", freedMB: mb))
        return [CleanupEngineResult(label: "IDE / Electron caches", freedMB: mb)]
    }

    // MARK: 9b. Old IDE Versions

    func cleanIDEOldVersions(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning old IDE versions and leftover caches..."))
        var freed: Int64 = 0

        // 1. System-level IDE caches (safe, regenerated automatically)
        let systemCacheDirs = [
            // VS Code
            "\(home)/Library/Caches/com.microsoft.VSCode",
            // Cursor
            "\(home)/Library/Caches/Cursor",
            // Windsurf
            "\(home)/Library/Caches/com.exafunction.windsurf",
            "\(home)/Library/Caches/com.exafunction.windsurf.ShipIt",
            // Zed
            "\(home)/Library/Caches/dev.zed.Zed",
            "\(home)/.cache/zed",
            // Nova
            "\(home)/Library/Caches/com.panic.Nova",
            // Sublime Text
            "\(home)/Library/Caches/com.sublimetext.4",
            "\(home)/Library/Caches/com.sublimetext.sublime-merge",
            // Eclipse
            "\(home)/Library/Caches/org.eclipse.platform.ide",
            // Atom (legacy)
            "\(home)/Library/Caches/com.github.atom",
            "\(home)/Library/Caches/Atom",
        ]

        for dir in systemCacheDirs {
            try Task.checkCancellation()
            let (f, item) = try await cleanContents(of: dir, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Old IDE Versions", parentName: nil, progress: progress) }
        }

        // 2. JetBrains: detect old product version dirs for no-longer-installed IDEs
        progress?(.log("  Checking JetBrains products..."))
        let installedJetBrainsProducts = collectInstalledJetBrainsProducts()
        let jetBrainsCacheBase = "\(home)/Library/Caches/JetBrains"
        let jetBrainsLogBase = "\(home)/Library/Logs/JetBrains"

        for base in [jetBrainsCacheBase, jetBrainsLogBase] {
            guard fm.fileExists(atPath: base) else { continue }
            let entries = (try? fm.contentsOfDirectory(atPath: base)) ?? []
            for entry in entries {
                try Task.checkCancellation()
                guard !entry.hasPrefix(".") else { continue }
                // Check if this product dir matches an installed IDE
                let isInstalled = installedJetBrainsProducts.contains { product in
                    entry.lowercased().hasPrefix(product.lowercased())
                }
                if !isInstalled {
                    let entryPath = "\(base)/\(entry)"
                    let (f, item) = try await removeDirectory(entryPath, dryRun: dryRun, progress: progress)
                    freed += f
                    if dryRun { emitFileItem(item, category: "Old IDE Versions", parentName: "JetBrains leftover: \(entry)", progress: progress) }
                } else {
                    // Product IS installed — still clean caches (safe, regenerated)
                    // but only for the cache dir, not logs
                    if base == jetBrainsCacheBase {
                        let entryPath = "\(base)/\(entry)"
                        let (f, item) = try await cleanContents(of: entryPath, dryRun: dryRun, progress: progress)
                        freed += f
                        if dryRun { emitFileItem(item, category: "Old IDE Versions", parentName: "JetBrains cache: \(entry)", progress: progress) }
                    }
                }
            }
        }

        // 3. Android Studio: clean caches for old versions (keep only latest per product line)
        progress?(.log("  Checking Android Studio caches..."))
        let asCandidates = [
            "\(home)/Library/Caches/Google/AndroidStudio",
            "\(home)/Library/Caches/AndroidStudio",
        ]
        for candidateBase in asCandidates {
            let baseDir = URL(fileURLWithPath: candidateBase).deletingLastPathComponent().path
            let prefix = URL(fileURLWithPath: candidateBase).lastPathComponent
            guard fm.fileExists(atPath: baseDir) else { continue }
            let entries = (try? fm.contentsOfDirectory(atPath: baseDir)) ?? []
            let matching = entries.filter { $0.hasPrefix(prefix) && !$0.hasPrefix(".") }.sorted()
            // Keep the last one (latest version), remove older ones
            if matching.count > 1 {
                for old in matching.dropLast() {
                    let oldPath = "\(baseDir)/\(old)"
                    let (f, item) = try await removeDirectory(oldPath, dryRun: dryRun, progress: progress)
                    freed += f
                    if dryRun { emitFileItem(item, category: "Old IDE Versions", parentName: "Android Studio old: \(old)", progress: progress) }
                }
            }
        }

        // 4. VS Code / Cursor / Windsurf CachedData — each subdir is a version, old ones can be cleaned
        let electronAppSupportBases = [
            ("\(home)/Library/Application Support/Code", "Code"),
            ("\(home)/Library/Application Support/Code - Insiders", "Code - Insiders"),
            ("\(home)/Library/Application Support/Cursor", "Cursor"),
            ("\(home)/Library/Application Support/Windsurf", "Windsurf"),
        ]
        for (appSupportPath, appName) in electronAppSupportBases {
            let cachedDataPath = "\(appSupportPath)/CachedData"
            guard fm.fileExists(atPath: cachedDataPath) else { continue }
            let entries = (try? fm.contentsOfDirectory(atPath: cachedDataPath)) ?? []
            if entries.count > 1 {
                // Has multiple version subdirs — clean old ones
                let sorted = entries.filter { $0 != "CachedData" && !$0.hasPrefix(".") }.sorted()
                if sorted.count > 1 {
                    for old in sorted.dropLast() {
                        let oldPath = "\(cachedDataPath)/\(old)"
                        var isDir: ObjCBool = false
                        fm.fileExists(atPath: oldPath, isDirectory: &isDir)
                        guard isDir.boolValue else { continue }
                        let (f, item) = try await removeDirectory(oldPath, dryRun: dryRun, progress: progress)
                        freed += f
                        if dryRun { emitFileItem(item, category: "Old IDE Versions", parentName: "\(appName) old CachedData", progress: progress) }
                    }
                }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Old IDE versions total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Old IDE versions", freedMB: mb))
        return [CleanupEngineResult(label: "Old IDE Versions", freedMB: mb)]
    }

    /// Collects installed JetBrains product names from /Applications.
    private func collectInstalledJetBrainsProducts() -> [String] {
        let searchPaths = ["/Applications", "\(fileSystemContext.homePath)/Applications"]
        var products: [String] = []
        let jetBrainsBundlePrefixes = [
            "com.jetbrains.", "com.google.AndroidStudio"
        ]
        // Map bundle ID suffixes to product directory name used in caches/logs
        let productNameMap: [String: String] = [
            "intellij": "IntelliJIdea",
            "intellij.ce": "IntelliJIdea",
            "intellij.ue": "IntelliJIdea",
            "pycharm": "PyCharm",
            "pycharm.ce": "PyCharm",
            "pycharm.pe": "PyCharm",
            "webstorm": "WebStorm",
            "clion": "CLion",
            "goland": "GoLand",
            "goland.ce": "GoLand",
            "rider": "Rider",
            "dataspell": "DataSpell",
            "rubymine": "RubyMine",
            "phpstorm": "PhpStorm",
            "dotmemory": "dotMemory",
            "dotcover": "dotCover",
            "dottrace": "dotTrace",
            "resharper": "ReSharper",
            "fleet": "Fleet",
            "aqua": "Aqua",
            "idea": "IntelliJIdea",
            "AndroidStudio": "AndroidStudio",
        ]
        for basePath in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appPath = "\(basePath)/\(item)"
                guard let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
                      let bundleID = bundle.bundleIdentifier?.lowercased() else { continue }
                guard jetBrainsBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) else { continue }
                // Extract the product part after prefix
                let productKey = bundleID
                    .replacingOccurrences(of: "com.jetbrains.", with: "")
                    .replacingOccurrences(of: "com.google.", with: "")
                    .replacingOccurrences(of: "-eap", with: "")
                if let mapped = productNameMap[productKey] {
                    products.append(mapped)
                } else {
                    // Fallback: use capitalized last component
                    let parts = productKey.components(separatedBy: ".")
                    if let last = parts.last?.capitalized {
                        products.append(last)
                    }
                }
            }
        }
        return products
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
        let dfCommand = "docker -H \(dockerHost) system df --format '{{.Reclaimable}}' 2>/dev/null"
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

        if dryRun {
            if totalReclaimableMB > 0 {
                progress?(.log("  Total reclaimable: ~\(totalReclaimableMB) MB"))
                progress?(.result(label: "Docker reclaimable space", freedMB: totalReclaimableMB))
                let dockerRoot = dockerHost.hasPrefix("unix://") ? dockerHost.replacingOccurrences(of: "unix://", with: "") : "/var/lib/docker"
                emitFileItem(CleanupFileItem(path: dockerRoot, sizeBytes: Int64(totalReclaimableMB) * 1024 * 1024, modificationDate: nil, isDirectory: true), category: "Docker", parentName: nil, progress: progress)
            } else {
                progress?(.log("  Nothing reclaimable"))
                progress?(.log("Docker: nothing reclaimable"))
            }
            return [CleanupEngineResult(label: "Docker", freedMB: totalReclaimableMB)]
        } else {
            let pruneCommand = "docker -H \(dockerHost) system prune -af --volumes 2>/dev/null"
            progress?(.log("  Running: \(pruneCommand)"))
            _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", pruneCommand])
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

    func cleanLanguageCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?, cleanModCache: Bool = false) async throws -> [CleanupEngineResult] {
        _ = cleanModCache
        return try await cleanFromEmbeddedPaths(.languageCaches, label: "Language caches", dryRun: dryRun, progress: progress)
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
            let containers = try? fm.contentsOfDirectory(atPath: containersPath)
            let containerCount = (containers ?? []).count
            progress?(.log("  Found \(containerCount) containers in \(shortPath(containersPath))"))
            var scannedCount = 0
            for container in (containers ?? []) {
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

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let windowsMetaNames: Set<String> = ["Thumbs.db", "desktop.ini", "ehthumbs.db"]

        for await batch in scanner.scanParallel(
            roots: scanDirs,
            config: .init(
                excludedPrefixes: ["/Library/", "/.Trash/", "/.git/"],
                maxDepth: nil,
                batchSize: 1000,
                yieldInterval: .seconds(2)
            ),
            progress: { scanned, _ in
                progress?(.log("  Scanned \(scanned) files..."))
            }
        ) {
            try Task.checkCancellation()

            for entry in batch {
                scannedCount += 1

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

    func cleanOrphanedRemnants(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Unattended orphan deletion is disabled — heuristics can match live apps.
        // Scan remains available for UI review; never auto-trash from cleanup/scheduled.
        progress?(.log("Orphaned remnants: skipped (manual review only; never auto-delete)"))
        progress?(.result(label: "Orphaned remnants", freedMB: 0))
        return [CleanupEngineResult(label: "Orphaned remnants", freedMB: 0)]
    }

    // MARK: 20. Orphaned Files

    func cleanOrphanedFiles(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Orphaned files: skipped (manual review only; never auto-delete)"))
        progress?(.result(label: "Orphaned files", freedMB: 0))
        return [CleanupEngineResult(label: "Orphaned files", freedMB: 0)]
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
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
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

        // node_modules directories > 100MB (recursive search)
        progress?(.log("  Scanning home directory for node_modules > 100 MB..."))
        let searchDirs = [home]
        for baseDir in searchDirs {
            guard fm.fileExists(atPath: baseDir) else { continue }
            guard let enumerator = fm.enumerator(atPath: baseDir) else { continue }
            while let item = enumerator.nextObject() as? String {
                try Task.checkCancellation()
                let fullPath = "\(baseDir)/\(item)"
                // Skip hidden dirs, Library
                if item.hasPrefix(".") || fullPath.contains("/Library/") {
                    enumerator.skipDescendants()
                    continue
                }
                // Skip heavy directories (Docker, VMs, etc.) — only for actual directories
                if Self.isHeavyDirectory(fullPath) {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                    if isDir.boolValue {
                        progress?(.log("  Skipping heavy directory: \(shortPath(fullPath))"))
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if item == "node_modules" {
                    let size = await getDirectorySizeWithTimeout(fullPath, timeout: .seconds(10))
                    if size > 100 * 1024 * 1024 {
                        items.append(("\(fullPath.replacingOccurrences(of: home, with: "~"))", size))
                        totalFound += size
                        if dryRun {
                            emitFileItem(CleanupFileItem(path: fullPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Large files", parentName: "Large files", progress: progress)
                        }
                    }
                    enumerator.skipDescendants()
                }
            }
        }

        // IPSW firmware files
        progress?(.log("  Scanning for IPSW firmware files..."))
        let ipswSearchDirs = [home, "/tmp"]
        for dir in ipswSearchDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            guard let enumerator = fm.enumerator(atPath: dir) else { continue }
            while let item = enumerator.nextObject() as? String {
                try Task.checkCancellation()
                // Skip heavy directories in IPSW search too
                let fullPath = "\(dir)/\(item)"
                if Self.isHeavyDirectory(fullPath) {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                    if isDir.boolValue { enumerator.skipDescendants() }
                    continue
                }
                let ext = (item as NSString).pathExtension.lowercased()
                if ext == "ipsw" {
                    if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int64, size > 100 * 1024 * 1024 {
                        items.append(("IPSW: \(item)", size))
                        totalFound += size
                        if dryRun {
                            emitFileItem(CleanupFileItem(path: fullPath, sizeBytes: size, modificationDate: nil, isDirectory: false), category: "Large files", parentName: "Large files", progress: progress)
                        }
                    }
                }
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
            } else {
                // In cleanup mode: only auto-clean safe patterns >= threshold
                if isSafePattern && size >= minSizeForAutoClean {
                    let entryURL = URL(fileURLWithPath: entryPath)
                    do {
                        try safetyManager.validate(url: entryURL)
                        try? fm.removeItem(atPath: entryPath)
                        progress?(.log("  ✓ Removed \(entry) — \(Self.formatBytes(size))"))
                        freed += size
                    } catch {
                        progress?(.log("  Skipped \(entry) — safety check failed"))
                    }
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

        progress?(.log("  Found \(snapshots.count) local snapshots"))

        if dryRun {
            for snap in snapshots {
                progress?(.log("  ⊘ \(snap.name)"))
            }
            progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
        }

        var deleted = 0
        for snap in snapshots {
            try Task.checkCancellation()
            do {
                _ = try await PrivilegedTaskRunner.runAsAdmin(command: "/usr/bin/tmutil deletelocalsnapshots \(snap.name)")
                deleted += 1
                progress?(.log("  ✓ Deleted \(snap.name)"))
            } catch {
                progress?(.log("  ✗ Failed to delete \(snap.name): \(error.localizedDescription)"))
            }
        }

        progress?(.log("  Deleted \(deleted) snapshots"))
        progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
        return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
    }

    // MARK: 24. iOS Backups

    func cleanIOSBackups(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning iOS backups..."))

        let backupDir = "\(home)/Library/Application Support/MobileSync/Backup"
        let (freed, item) = try await cleanContents(of: backupDir, dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "iOS Backups", parentName: nil, progress: progress) }

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
            if dryRun { emitFileItem(item, category: "Mail Downloads", parentName: nil, progress: progress) }
        }

        // Enhanced: Mail Attachments from cleanup.json
        let mailDir = "\(home)/Library/Mail"
        if fm.fileExists(atPath: mailDir) {
            let mailAccounts = (try? fm.contentsOfDirectory(atPath: mailDir)) ?? []
            for account in mailAccounts {
                let attachmentsPath = "\(mailDir)/\(account)/Attachments"
                let (f, item) = try await cleanContents(of: attachmentsPath, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Mail Downloads", parentName: "Mail Attachments", progress: progress) }
            }
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
        if dryRun { emitFileItem(item, category: "Saved Application State", parentName: nil, progress: progress) }

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
        let home = fileSystemContext.homePath
        progress?(.log("Scanning SwiftPM cache..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/.swiftpm/cache",
            "\(home)/Library/Caches/org.swift.swiftpm"
        ]

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
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Carthage cache..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/Library/Caches/org.carthage.CarthageKit",
            "\(home)/.cocoapods/repos"
        ]

        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Carthage Cache", parentName: nil, progress: progress) }
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

    func cleanLaunchAgents(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Wholesale LaunchAgents cleanup is disabled — only proven app-owned plists via uninstaller.
        progress?(.log("Launch Agents: skipped (requires per-app ownership; use Uninstaller)"))
        progress?(.result(label: "Launch Agents", freedMB: 0))
        return [CleanupEngineResult(label: "Launch Agents", freedMB: 0)]
    }

    // MARK: 37. Launch Daemons (system)

    func cleanLaunchDaemons(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Launch Daemons: skipped (requires per-app ownership; use Uninstaller)"))
        progress?(.result(label: "Launch Daemons", freedMB: 0))
        return [CleanupEngineResult(label: "Launch Daemons", freedMB: 0)]
    }

    // MARK: 38. Privileged Helper Tools

    func cleanPrivilegedHelpers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Privileged Helper Tools: skipped (requires per-app ownership; use Uninstaller)"))
        progress?(.result(label: "Privileged Helper Tools", freedMB: 0))
        return [CleanupEngineResult(label: "Privileged Helper Tools", freedMB: 0)]
    }

    // MARK: 39. Package Receipts

    func cleanPkgReceipts(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning package receipts..."))
        var freed: Int64 = 0
        let paths = [
            "\(home)/Library/Receipts",
            "/Library/Receipts",
        ]
        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Package Receipts", parentName: nil, progress: progress) }
        }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Package Receipts", freedMB: mb))
        return [CleanupEngineResult(label: "Package Receipts", freedMB: mb)]
    }

    // MARK: 40. Internet Plugins

    func cleanInternetPlugins(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning internet plugins..."))
        var freed: Int64 = 0
        let paths = [
            "\(home)/Library/Internet Plug-Ins",
            "/Library/Internet Plug-Ins",
        ]
        for path in paths {
            guard fm.fileExists(atPath: path) else { continue }
            let (f, item) = try await removeDirectory(path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Internet Plugins", parentName: nil, progress: progress) }
        }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Internet Plugins", freedMB: mb))
        return [CleanupEngineResult(label: "Internet Plugins", freedMB: mb)]
    }

    // MARK: 41. Shared File Lists

    func cleanSharedFileLists(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning shared file lists..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/Application Support/com.apple.sharedfilelist", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Shared File Lists", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Shared File Lists", freedMB: mb))
        return [CleanupEngineResult(label: "Shared File Lists", freedMB: mb)]
    }

    // MARK: 42. Cloud Docs

    func cleanCloudDocs(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // CloudDocs holds user iCloud Drive content — never wholesale-clean.
        progress?(.log("Cloud Docs: skipped (user cloud content; never auto-delete)"))
        progress?(.result(label: "Cloud Docs", freedMB: 0))
        return [CleanupEngineResult(label: "Cloud Docs", freedMB: 0)]
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

    // MARK: 44. Voice Memos

    func cleanVoiceMemos(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning Voice Memos..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/Application Support/com.apple.VoiceMemos/Recordings", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Voice Memos", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Voice Memos", freedMB: mb))
        return [CleanupEngineResult(label: "Voice Memos", freedMB: mb)]
    }

    // MARK: 45. GarageBand / Logic Pro

    func cleanGarageBandLogic(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning GarageBand / Logic Pro..."))
        var freed: Int64 = 0
        let paths = [
            "\(home)/Music/GarageBand",
            "\(home)/Music/Logic",
            "\(home)/Library/Containers/com.apple.garageband10/Data/Library/Caches",
        ]
        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "GarageBand / Logic Pro", parentName: nil, progress: progress) }
        }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "GarageBand / Logic Pro", freedMB: mb))
        return [CleanupEngineResult(label: "GarageBand / Logic Pro", freedMB: mb)]
    }

    // MARK: 46. iMovie / Final Cut

    func cleanIMovieFinalCut(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fileSystemContext.homePath
        progress?(.log("Scanning iMovie / Final Cut..."))
        var freed: Int64 = 0
        let paths = [
            "\(home)/Movies/iMovie Library.imovielibrary",
            "\(home)/Movies/Final Cut Pro Libraries",
            "\(home)/Library/Caches/com.apple.iMovieApp",
        ]
        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "iMovie / Final Cut", parentName: nil, progress: progress) }
        }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "iMovie / Final Cut", freedMB: mb))
        return [CleanupEngineResult(label: "iMovie / Final Cut", freedMB: mb)]
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

    // MARK: 49b. Installer packages (DMG / PKG / ISO)

    func cleanInstallerPackages(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Review-only: surface old installers for explicit selection.
        let home = fileSystemContext.homePath
        let label = "Installer Packages"
        let minAgeDays = 7
        let minSize: Int64 = 20 * 1024 * 1024 // 20 MB — skip tiny stubs
        let cutoff = Date().addingTimeInterval(TimeInterval(-minAgeDays * 24 * 60 * 60))
        let roots = ["Downloads", "Desktop", "Documents"].map { "\(home)/\($0)" }
        progress?(.log("Scanning installer packages (dmg/pkg/iso, age ≥ \(minAgeDays)d or large; opt-in)..."))

        var totalBytes: Int64 = 0
        var found = 0
        var skipped = 0

        for root in roots {
            try Task.checkCancellation()
            guard fm.fileExists(atPath: root) else { continue }
            let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
            for name in entries {
                try Task.checkCancellation()
                let ext = (name as NSString).pathExtension.lowercased()
                guard ["dmg", "pkg", "iso"].contains(ext) else { continue }
                let path = "\(root)/\(name)"
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int64, size >= minSize else {
                    skipped += 1
                    continue
                }
                let modified = attrs[.modificationDate] as? Date
                // Keep recent small-ish installers; always surface very large ones (≥200 MB).
                let isOld = (modified ?? .distantPast) < cutoff
                let isVeryLarge = size >= 200 * 1024 * 1024
                guard isOld || isVeryLarge else {
                    skipped += 1
                    continue
                }
                found += 1
                totalBytes += size
                progress?(.fileItem(
                    path: path,
                    sizeBytes: size,
                    modificationDate: modified,
                    isDirectory: false,
                    category: label,
                    parentName: label
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

    // MARK: 50. DNS Flush

    func cleanDNSFlush(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Flushing DNS cache..."))
        if dryRun {
            progress?(.log("  Would run: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"))
            progress?(.result(label: "DNS Cache", freedMB: 0))
            return [CleanupEngineResult(label: "DNS Cache", freedMB: 0)]
        }
        let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"])
        if result?.exitCode == 0 {
            progress?(.log("  DNS cache flushed successfully"))
        } else {
            progress?(.log("  DNS cache flush failed (may need sudo without password)"))
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
            progress?(.result(label: "Font Cache", freedMB: 0))
            return [CleanupEngineResult(label: "Font Cache", freedMB: 0)]
        }
        let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "sudo atsutil databases -remove"])
        if result?.exitCode == 0 {
            progress?(.log("  Font cache cleared — restart required"))
        } else {
            progress?(.log("  Font cache clear failed (may need sudo without password)"))
        }
        progress?(.result(label: "Font Cache", freedMB: 0))
        return [CleanupEngineResult(label: "Font Cache", freedMB: 0)]
    }

    // MARK: 51. Sleep Image

    func cleanSleepImage(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Checking sleep image..."))
        let size = await getDirectorySize("/var/vm/sleepimage")
        if size > 0 {
            progress?(.log("  Sleep image: \(Self.formatBytes(size))"))
            if dryRun {
                progress?(.log("  Would disable hibernation and remove sleep image"))
                emitFileItem(CleanupFileItem(path: "/var/vm/sleepimage", sizeBytes: size, modificationDate: nil, isDirectory: false), category: "Sleep Image", parentName: nil, progress: progress)
                progress?(.result(label: "Sleep Image", freedMB: Int(size / (1024 * 1024))))
                return [CleanupEngineResult(label: "Sleep Image", freedMB: Int(size / (1024 * 1024)))]
            }
            let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "sudo pmset hibernatemode 0; sudo rm /var/vm/sleepimage"])
            if result?.exitCode == 0 {
                progress?(.log("  Sleep image removed, hibernation disabled"))
                progress?(.result(label: "Sleep Image", freedMB: Int(size / (1024 * 1024))))
                return [CleanupEngineResult(label: "Sleep Image", freedMB: Int(size / (1024 * 1024)))]
            } else {
                progress?(.log("  Failed to remove sleep image"))
            }
        } else {
            progress?(.log("  No sleep image found"))
        }
        progress?(.result(label: "Sleep Image", freedMB: 0))
        return [CleanupEngineResult(label: "Sleep Image", freedMB: 0)]
    }

    // MARK: 52. Duplicate Files (scanning only — stub)

    func cleanDuplicateFiles(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("  Duplicate detection requires sha256 — recommend dedicated tool"))
        progress?(.log("  Skipping — not implemented"))
        progress?(.result(label: "Duplicate Files", freedMB: 0))
        return [CleanupEngineResult(label: "Duplicate Files", freedMB: 0)]
    }

    // MARK: 53. Unused Apps (scanning only)

    func cleanUnusedApps(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Scanning for unused apps..."))
        progress?(.log("  Checking apps not launched in 180 days..."))

        let appPaths = ["/Applications", "\(fileSystemContext.homePath)/Applications", "/Applications/Setapp"]
        var unusedApps: [(String, String, Date?)] = []

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -180, to: Date())!

        for basePath in appPaths {
            guard fm.fileExists(atPath: basePath) else { continue }
            guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appPath = "\(basePath)/\(item)"
                guard let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
                      let bundleID = bundle.bundleIdentifier else { continue }
                // Skip Apple apps
                if bundleID.hasPrefix("com.apple.") { continue }
                // Check last launch date via spotlight metadata
                let mdItem = MDItemCreate(nil, appPath as CFString)
                if let mdItem = mdItem {
                    if let lastUsed = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date {
                        if lastUsed < cutoffDate {
                            unusedApps.append((item.replacingOccurrences(of: ".app", with: ""), appPath, lastUsed))
                        }
                    }
                }
            }
        }

        if dryRun {
            for (name, path, lastUsed) in unusedApps {
                let dateStr = lastUsed.map { fmtDate($0) } ?? "unknown"
                progress?(.log("  \(name) — last used: \(dateStr) [\(shortPath(path))]"))
            }
        }
        progress?(.log("  Found \(unusedApps.count) potentially unused apps"))
        progress?(.log("  Unused apps are for review only — no automatic deletion"))
        progress?(.result(label: "Unused Apps", freedMB: 0))
        return [CleanupEngineResult(label: "Unused Apps", freedMB: 0)]
    }

    private func fmtDate(_ date: Date) -> String {
        DateFormatter.makeLocalized(dateStyle: .medium).string(from: date)
    }
}


