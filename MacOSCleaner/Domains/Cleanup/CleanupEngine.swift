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

    public init(label: String, freedMB: Int) {
        self.label = label
        self.freedMB = freedMB
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
    private let fm = FileManager.default
    let fileActor: FileCleanupActor
    let processActor: ProcessCleanupActor
    let scanActor: ScanActor
    let sizeCache: DirectorySizeCache

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        safetyManager: SafetyManager = SafetyManager(),
        timeouts: CleanupTimeouts = .default
    ) {
        self.commandRunner = commandRunner
        self.safetyManager = safetyManager
        self.timeouts = timeouts
        self.sizeCache = DirectorySizeCache()
        self.fileActor = FileCleanupActor(safetyManager: safetyManager, sizeCache: DirectorySizeCache())
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

        let maxConcurrency = ProcessInfo.processInfo.activeProcessorCount

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
        case .dnsFlush: return try await cleanDNSFlush(dryRun: dryRun, progress: progress)
        case .fontCache: return try await cleanFontCache(dryRun: dryRun, progress: progress)
        case .sleepImage: return try await cleanSleepImage(dryRun: dryRun, progress: progress)
        case .duplicateFiles: return try await cleanDuplicateFiles(dryRun: dryRun, progress: progress)
        case .unusedApps: return try await cleanUnusedApps(dryRun: dryRun, progress: progress)
        }
    }

    private static func timeoutForCategory(_ category: CleanupCategory) -> Duration {
        switch category {
        case .packageManagers, .docker, .languageCaches, .androidSDK, .timeMachineSnapshots, .ideOldVersions:
            return .seconds(120)
        case .xcode, .iosSimulators:
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

    public init(cleanDSStore: Bool = false, cleanMaven: Bool = true, cleanModCache: Bool = true, cleanProjects: Bool = true, xcodeArchivesOlderThanDays: Int = 90, cleanCloudDocs: Bool = false, cleanVoiceMemos: Bool = false, cleanGarageBandLogic: Bool = false, cleanIMovieFinalCut: Bool = false, cleanSleepImage: Bool = false) {
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
    }

    /// Returns ALL categories for scanning (like the shell script always does).
    public func scanCategories() -> [CleanupCategory] {
        return CleanupCategory.allCases
    }

    /// Returns the set of categories to actually clean based on these options.
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
            .orphanedRemnants,
            .orphanedFiles,
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
            .timeMachineSnapshots,
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
            .launchAgents,
            .launchDaemons,
            .privilegedHelpers,
            .pkgReceipts,
            .internetPlugins,
            .sharedFileLists,
            .photosCache,
            .garminFitbit,
            .oldBackups,
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

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning app caches..."))

        let cacheDirs = [
            "\(home)/Library/Caches/Google",
            "\(home)/Library/Caches/com.google.SoftwareUpdate",
            "\(home)/Library/Caches/com.google.GoogleUpdater",
            "\(home)/Library/Application Support/Google/GoogleUpdater",
            "\(home)/Library/Google/GoogleSoftwareUpdate",
            "\(home)/Library/HTTPStorages/com.google.GoogleUpdater",
            "\(home)/Library/Caches/org.carthage.CarthageKit",
            "\(home)/Library/Caches/CocoaPods",
            "\(home)/Library/Caches/pip",
            "\(home)/Library/Caches/Homebrew",
            "\(home)/Library/Caches/ms-playwright-go",
            "\(home)/Library/Caches/com.spotify.client",
            "\(home)/Library/Caches/com.apple.dt.Xcode",
            "\(home)/Library/Caches/com.apple.dt.instruments",
            "\(home)/Library/Caches/org.swift.swiftpm",
            "\(home)/Library/Caches/com.plausiblelabs.crashreporter.data",
            "\(home)/Library/Caches/JetBrains",
            "\(home)/Library/Caches/@opencode-aidesktop-updater"
        ]

        var totalFreed: Int64 = 0
        for dir in cacheDirs {
            try Task.checkCancellation()
            let (freed, item) = try await cleanContents(of: dir, dryRun: dryRun, progress: progress)
            totalFreed += freed
            if dryRun { emitFileItem(item, category: "App caches", parentName: nil, progress: progress) }
        }

        // Google Updater Plists
        progress?(.log("Removing Google Updater plists..."))
        let plistPaths = [
            "\(home)/Library/Preferences/com.google.Keystone.Agent.plist",
            "\(home)/Library/LaunchAgents/com.google.keystone.xpcservice.plist",
            "\(home)/Library/LaunchAgents/com.google.keystone.agent.plist",
            "\(home)/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist"
        ]
        for plist in plistPaths {
            try Task.checkCancellation()
            let (freed, item) = try await removeFile(plist, dryRun: dryRun, progress: progress)
            totalFreed += freed
            if dryRun { emitFileItem(item, category: "App caches", parentName: nil, progress: progress) }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("App caches total: \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: "Selected app caches", freedMB: mb))
        return [CleanupEngineResult(label: "Selected app caches", freedMB: mb)]
    }

    // MARK: 2. Package Managers (FileManager + Process)

    func cleanPackageManagers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        var results: [CleanupEngineResult] = []
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Checking package managers..."))

        // Homebrew
        if await commandRunner.commandExists("brew") {
            progress?(.log("  Homebrew detected"))
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("brew --cache 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheDir = cachePath ?? "\(home)/Library/Caches/Homebrew"
            progress?(.log("  Cache path: \(Self.shortPath(cacheDir))"))

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
            progress?(.log("  Cache path: \(Self.shortPath(cacheDir))"))

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
            progress?(.log("  Cache path: \(Self.shortPath(cacheDir))"))

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
            progress?(.log("  Store path: \(Self.shortPath(storeDir))"))

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
            progress?(.log("  Cache path: \(Self.shortPath(cacheDir))"))

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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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

    // MARK: 6. iOS Simulators

    func cleanIOSSimulators(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
                progress?(.log("  sdkmanager found at \(Self.shortPath(path))"))
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
        let home = fm.homeDirectoryForCurrentUser.path

        let ideDirs = [
            // Cursor
            "\(home)/Library/Application Support/Cursor/Cache",
            "\(home)/Library/Application Support/Cursor/CachedData",
            "\(home)/Library/Application Support/Cursor/Code Cache",
            "\(home)/Library/Application Support/Cursor/CachedExtensionVSIXs",
            "\(home)/Library/Application Support/Cursor/User/workspaceStorage",
            "\(home)/Library/Application Support/Cursor/Crashpad",
            "\(home)/Library/Application Support/Cursor/Session Storage",
            "\(home)/Library/Application Support/Cursor/Service Worker",
            // VS Code
            "\(home)/Library/Application Support/Code/Cache",
            "\(home)/Library/Application Support/Code/CachedData",
            "\(home)/Library/Application Support/Code/CachedExtensionVSIXs",
            "\(home)/Library/Application Support/Code/User/workspaceStorage",
            "\(home)/Library/Application Support/Code/Crashpad",
            "\(home)/Library/Application Support/Code/Session Storage",
            "\(home)/Library/Application Support/Code/Service Worker",
            // VS Code Insiders
            "\(home)/Library/Application Support/Code - Insiders/Cache",
            "\(home)/Library/Application Support/Code - Insiders/CachedData",
            "\(home)/Library/Application Support/Code - Insiders/CachedExtensionVSIXs",
            "\(home)/Library/Application Support/Code - Insiders/User/workspaceStorage",
            "\(home)/Library/Application Support/Code - Insiders/Crashpad",
            "\(home)/Library/Application Support/Code - Insiders/Session Storage",
            "\(home)/Library/Application Support/Code - Insiders/Service Worker",
            // Windsurf
            "\(home)/Library/Application Support/Windsurf/Cache",
            "\(home)/Library/Application Support/Windsurf/CachedData",
            "\(home)/Library/Application Support/Windsurf/Code Cache",
            "\(home)/Library/Application Support/Windsurf/CachedExtensionVSIXs",
            "\(home)/Library/Application Support/Windsurf/User/workspaceStorage",
            "\(home)/Library/Application Support/Windsurf/Crashpad",
            "\(home)/Library/Application Support/Windsurf/Session Storage",
            "\(home)/Library/Application Support/Windsurf/Service Worker",
            // Zed
            "\(home)/Library/Application Support/dev.zed.Zed/cache",
            "\(home)/.config/zed/cache",
            // opencode Desktop
            "\(home)/Library/Application Support/ai.opencode.desktop/Cache",
            "\(home)/Library/Application Support/ai.opencode.desktop/CachedData",
            "\(home)/Library/Application Support/ai.opencode.desktop/Code Cache",
            "\(home)/Library/Application Support/ai.opencode.desktop/CachedExtensionVSIXs",
            "\(home)/Library/Application Support/ai.opencode.desktop/User/workspaceStorage",
            "\(home)/Library/Application Support/ai.opencode.desktop/Crashpad",
            "\(home)/Library/Application Support/ai.opencode.desktop/Session Storage",
            "\(home)/Library/Application Support/ai.opencode.desktop/Service Worker",
            // Nova (Panic)
            "\(home)/Library/Application Support/Nova/Caches",
            "\(home)/Library/Caches/com.panic.Nova",
            // Sublime Text 4
            "\(home)/Library/Application Support/Sublime Text/Cache",
            "\(home)/Library/Application Support/Sublime Text/Index",
            "\(home)/Library/Application Support/Sublime Text/Package Control.cache",
            "\(home)/Library/Caches/com.sublimetext.4",
            // Sublime Merge
            "\(home)/Library/Caches/com.sublimetext.sublime-merge",
            // Atom (legacy)
            "\(home)/Library/Application Support/Atom/Cache",
            "\(home)/Library/Application Support/Atom/CachedData",
            "\(home)/Library/Application Support/Atom/Crashpad",
            "\(home)/Library/Caches/com.github.atom",
            // Gemini
            "\(home)/Library/Application Support/Gemini/Cache",
            "\(home)/Library/Application Support/Gemini/CachedData",
            "\(home)/Library/Application Support/Gemini/Session Storage",
            // Perplexity
            "\(home)/Library/Application Support/Perplexity/Cache",
            "\(home)/Library/Application Support/Perplexity/CachedData",
            "\(home)/Library/Application Support/Perplexity/Session Storage",
            // GitHub Desktop
            "\(home)/Library/Application Support/GitHub Desktop/Cache",
            "\(home)/Library/Application Support/GitHub Desktop/CachedData",
            "\(home)/Library/Application Support/GitHub Desktop/Code Cache",
            "\(home)/Library/Application Support/GitHub Desktop/Session Storage",
            // 1Password
            "\(home)/Library/Caches/com.1password.1password",
            "\(home)/Library/Caches/com.agilebits.onepassword7",
            // Tower (Git client)
            "\(home)/Library/Caches/com.fournova.Tower3",
            // TablePlus
            "\(home)/Library/Caches/com.tinyapp.TablePlus",
            // Insomnia
            "\(home)/Library/Application Support/Insomnia/Cache",
            "\(home)/Library/Application Support/Insomnia/CachedData",
            "\(home)/Library/Application Support/Insomnia/Code Cache",
            // Claude
            "\(home)/Library/Application Support/Claude/Cache",
            "\(home)/Library/Application Support/Claude/CachedData",
            "\(home)/Library/Application Support/Claude/Code Cache",
            "\(home)/Library/Application Support/Claude/Session Storage",
            "\(home)/Library/Application Support/Claude/Service Worker",
            "\(home)/Library/Application Support/Claude/Crashpad",
            "\(home)/Library/Application Support/Claude/GPUCache",
            // ChatGPT
            "\(home)/Library/Application Support/ChatGPT/Cache",
            "\(home)/Library/Application Support/ChatGPT/CachedData",
            "\(home)/Library/Application Support/ChatGPT/Code Cache",
            "\(home)/Library/Application Support/ChatGPT/Session Storage",
            "\(home)/Library/Application Support/ChatGPT/Service Worker",
            "\(home)/Library/Application Support/ChatGPT/Crashpad",
            "\(home)/Library/Application Support/ChatGPT/GPUCache",
            // Slack
            "\(home)/Library/Application Support/Slack/Cache",
            "\(home)/Library/Application Support/Slack/CachedData",
            "\(home)/Library/Application Support/Slack/Code Cache",
            "\(home)/Library/Application Support/Slack/Service Worker",
            "\(home)/Library/Application Support/Slack/Session Storage",
            // Discord
            "\(home)/Library/Application Support/discord/Cache",
            "\(home)/Library/Application Support/discord/CachedData",
            "\(home)/Library/Application Support/discord/Code Cache",
            "\(home)/Library/Application Support/discord/Session Storage",
            "\(home)/Library/Application Support/discord/Crashpad",
            // Figma
            "\(home)/Library/Application Support/Figma/Cache",
            "\(home)/Library/Application Support/Figma/CachedData",
            "\(home)/Library/Application Support/Figma/Code Cache",
            "\(home)/Library/Application Support/Figma/Session Storage",
            // Notion
            "\(home)/Library/Application Support/Notion/Cache",
            "\(home)/Library/Application Support/Notion/CachedData",
            "\(home)/Library/Application Support/Notion/Code Cache",
            "\(home)/Library/Application Support/Notion/Session Storage",
            // JetBrains logs
            "\(home)/Library/Logs/JetBrains",
            // Postman
            "\(home)/Library/Application Support/Postman/Cache",
            "\(home)/Library/Application Support/Postman/CachedData",
            "\(home)/Library/Application Support/Postman/Code Cache",
            "\(home)/Library/Application Support/Postman/Session Storage",
            // Linear
            "\(home)/Library/Application Support/Linear/Cache",
            "\(home)/Library/Application Support/Linear/CachedData",
            "\(home)/Library/Application Support/Linear/Code Cache",
            "\(home)/Library/Application Support/Linear/Session Storage",
            // JetBrains Toolbox
            "\(home)/Library/Application Support/JetBrains/Toolbox/apps",
            "\(home)/Library/Caches/JetBrains",
            // Vivaldi
            "\(home)/Library/Caches/com.vivaldi.Vivaldi",
        ]

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

        // Dynamic discovery: find any unknown Electron app caches
        let appSupportPath = "\(home)/Library/Application Support"
        if fm.fileExists(atPath: appSupportPath) {
            let apps = (try? fm.contentsOfDirectory(atPath: appSupportPath)) ?? []
            for appDir in apps {
                try Task.checkCancellation()
                guard !knownApps.contains(appDir) else { continue }
                let cachePath = "\(appSupportPath)/\(appDir)/Cache"
                guard fm.fileExists(atPath: cachePath) else { continue }
                let size = await getDirectorySize(cachePath)
                guard size >= 5 * 1024 * 1024 else { continue } // skip < 5 MB
                let (freed, item) = try await cleanContents(of: cachePath, dryRun: dryRun, progress: progress)
                totalFreed += freed
                if dryRun { emitFileItem(item, category: "IDE / Electron caches", parentName: "\(appDir)/Cache", progress: progress) }
            }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("IDE / Electron total: \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: "IDE / Electron caches", freedMB: mb))
        return [CleanupEngineResult(label: "IDE / Electron caches", freedMB: mb)]
    }

    // MARK: 9b. Old IDE Versions

    func cleanIDEOldVersions(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let searchPaths = ["/Applications", "\(fm.homeDirectoryForCurrentUser.path)/Applications"]
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning browser caches..."))
        let browserDirs = [
            "\(home)/Library/Caches/com.apple.Safari",
            "\(home)/Library/Safari/Favicon Cache",
            "\(home)/Library/Caches/com.brave.Browser",
            "\(home)/Library/Caches/com.operasoftware.Opera",
            "\(home)/Library/Caches/com.microsoft.Edge",
            "\(home)/Library/Caches/org.mozilla.firefox",
            "\(home)/Library/Caches/Firefox",
            "\(home)/Library/Caches/com.google.Chrome",
            "\(home)/Library/Caches/com.google.Chrome.beta",
            "\(home)/Library/Caches/com.apple.WebKit.Networking",
            "\(home)/Library/Caches/BraveSoftware",
            "\(home)/Library/Caches/com.vivaldi.Vivaldi",
            "\(home)/Library/Caches/company.thebrowser.Browser",
        ]

        var totalFreed: Int64 = 0
        for dir in browserDirs {
            try Task.checkCancellation()
            let (freed, item) = try await cleanContents(of: dir, dryRun: dryRun, progress: progress)
            totalFreed += freed
            if dryRun { emitFileItem(item, category: "Browser caches", parentName: nil, progress: progress) }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("Browser caches total: \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: "Browser caches", freedMB: mb))
        return [CleanupEngineResult(label: "Browser caches", freedMB: mb)]
    }

    // MARK: 11. Messaging / Media

    func cleanMessagingMedia(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning messaging / media caches..."))
        let dirs = [
            "\(home)/Library/Caches/ru.keepcoder.Telegram",
            "\(home)/Library/Caches/com.tinyspeck.slackmacgap",
            "\(home)/Library/Caches/com.hnc.Discord",
            "\(home)/Library/Caches/com.spotify.client",
            "\(home)/Library/Caches/us.zoom.xos",
            "\(home)/Library/Messages/Attachments",
            "\(home)/Library/Caches/com.signal.Signal",
            "\(home)/Library/Caches/com.tencent.xinWeChat",
            "\(home)/Library/Caches/com.microsoft.teams2",
        ]

        var totalFreed: Int64 = 0
        for dir in dirs {
            try Task.checkCancellation()
            let (freed, item) = try await cleanContents(of: dir, dryRun: dryRun, progress: progress)
            totalFreed += freed
            if dryRun { emitFileItem(item, category: "Messaging / media", parentName: nil, progress: progress) }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("Messaging / media total: \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: "Messaging / media caches", freedMB: mb))
        return [CleanupEngineResult(label: "Messaging / media", freedMB: mb)]
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
        let home = fm.homeDirectoryForCurrentUser.path
        
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning language caches..."))
        var freed: Int64 = 0

        let cachePaths = [
            // Rust / Cargo
            "\(home)/.cargo/registry/cache",
            "\(home)/.cargo/registry/src",
            "\(home)/.cargo/.package-cache",
            // Bun
            "\(home)/.bun/install/cache",
            // Deno
            "\(home)/.deno/cache",
            "\(home)/Library/Caches/deno",
            // Volta
            "\(home)/.volta/cache",
            // NVM
            "\(home)/.nvm/.cache",
            // node-gyp
            "\(home)/.cache/node-gyp",
            "\(home)/.node-gyp",
            // Cypress
            "\(home)/.cache/Cypress",
            "\(home)/Library/Caches/Cypress",
            // Playwright
            "\(home)/.cache/ms-playwright",
            "\(home)/.cache/ms-playwright-go",
            "\(home)/Library/Caches/ms-playwright",
            // Puppeteer
            "\(home)/.cache/puppeteer",
            // PHP / Composer
            "\(home)/.composer/cache",
            // Python
            "\(home)/Library/Caches/pypoetry",
            "\(home)/Library/Caches/uv",
            "\(home)/.cache/pip",
            "\(home)/.cache/pypoetry",
            "\(home)/.cache/uv",
            "\(home)/.cache/hatch",
            "\(home)/.rye/cache",
            "\(home)/.cache/pipx",
            // JVM
            "\(home)/.sbt",
            "\(home)/.ivy2/cache",
            "\(home)/.coursier/cache",
            "\(home)/.ammonite/cache",
            "\(home)/.cache/metals",
            // Julia
            "\(home)/.julia/compiled",
            "\(home)/.julia/logs",
            // Elixir / Hex
            "\(home)/.hex/packages",
            // Haskell
            "\(home)/.cabal/packages",
            "\(home)/.cabal/logs",
            // Swift PM
            "\(home)/.cache/org.swift.swiftpm",
            // R session temp
            "\(home)/../tmp/org.R-project.R",
        ]
        for path in cachePaths {
            guard fm.fileExists(atPath: path) else { continue }
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Language caches", parentName: nil, progress: progress) }
        }

        // Ruby
        let gemRubyPath = "\(home)/.gem/ruby"
        if fm.fileExists(atPath: gemRubyPath) {
            let versions = try? fm.contentsOfDirectory(atPath: gemRubyPath)
            progress?(.log("  Ruby gems: \(versions?.count ?? 0) versions found"))
            for ver in (versions ?? []) {
                let (f, item) = try await cleanContents(of: "\(gemRubyPath)/\(ver)/cache", dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Language caches", parentName: nil, progress: progress) }
            }
        }
        let (bundleF, bundleItem) = try await cleanContents(of: "\(home)/.bundle/cache", dryRun: dryRun, progress: progress)
        freed += bundleF
        if dryRun { emitFileItem(bundleItem, category: "Language caches", parentName: nil, progress: progress) }

        // Go (build cache via command)
        if await commandRunner.commandExists("go") {
            progress?(.log("  Go runtime detected"))
            if dryRun {
                let goCachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go env GOCACHE 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let cachePath = goCachePath ?? "\(home)/Library/Caches/go-build"
                progress?(.log("  Go build cache: \(Self.shortPath(cachePath))"))
                let size = await getDirectorySize(cachePath)
                freed += size
                emitFileItem(CleanupFileItem(path: cachePath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Language caches", parentName: nil, progress: progress)
            } else {
                progress?(.log("  Running: go clean -cache"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go clean -cache 2>/dev/null")])
            }
        }

        // Go module cache — OPT-IN only
        if await commandRunner.commandExists("go") {
            let goModCache = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go env GOMODCACHE 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let modPath = goModCache ?? "\(home)/go/pkg/mod"
            progress?(.log("  Go module cache: \(Self.shortPath(modPath))"))
            if cleanModCache {
                let (f, item) = try await cleanContents(of: modPath, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Language caches", parentName: nil, progress: progress) }
            } else {
                let size = await getDirectorySize(modPath)
                progress?(.log("  Go module cache: \(Self.formatBytes(size)) — skipped (enable cleanModCache option to clean)"))
                if dryRun {
                    emitFileItem(CleanupFileItem(path: modPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Language caches", parentName: "Opt-in only", progress: progress)
                }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Language caches total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Language caches", freedMB: mb))
        return [CleanupEngineResult(label: "Language caches", freedMB: mb)]
    }

    // MARK: 14. User Logs

    func cleanUserLogs(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning system caches..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/Library/Caches/com.apple.QuickLook.thumbnailcache",
            "\(home)/Library/Caches/com.apple.fontd",
            "\(home)/Library/Caches/com.apple.iconservices",
            "\(home)/Library/Caches/com.apple.metadata.SpotlightIndex",
            "\(home)/Library/Caches/com.apple.Siri",
            "\(home)/Library/Caches/com.apple.Assistant",
            "\(home)/Library/Caches/com.apple.parsecd",
            "\(home)/Library/Caches/com.apple.helpd",
            "\(home)/Library/Caches/CloudKit",
            "\(home)/Library/Caches/com.apple.TimeMachine",
            "\(home)/Library/Caches/com.apple.diagnosticd",
            "\(home)/Library/Caches/com.apple.Spotlight",
        ]
        for path in paths {
            guard fm.fileExists(atPath: path) else { continue }
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "System caches", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("System caches total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "System caches", freedMB: mb))
        return [CleanupEngineResult(label: "System caches", freedMB: mb)]
    }

    // MARK: 16. App Containers

    func cleanAppContainers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
            progress?(.log("  Found \(containerCount) containers in \(Self.shortPath(containersPath))"))
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning dotfile caches..."))
        var freed: Int64 = 0

        // AI CLI tools
        let aiPaths = [
            "\(home)/.config/opencode/cache",
            "\(home)/.config/claude-cli/cache",
            "\(home)/.config/gemini/cache",
            "\(home)/.config/codex/cache",
            "\(home)/.config/aider/cache",
            "\(home)/.config/continue/cache",
            "\(home)/.config/cody/cache",
            "\(home)/.local/share/ollama/models",
        ]

        // Dev tool caches
        let devPaths = [
            "\(home)/.npm/_logs",
            "\(home)/.terraform.d/cache",
            "\(home)/.cache/helm/repository",
            "\(home)/.cache/bazel",
            "\(home)/.ccache",
            "\(home)/.vcpkg/cache",
        ]

        // Local Trash
        let trashPaths = [
            "\(home)/.local/share/Trash",
        ]

        let allPaths = aiPaths + devPaths + trashPaths
        for path in allPaths {
            guard fm.fileExists(atPath: path) else { continue }
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Dotfile caches", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Dotfile caches total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Dotfile caches", freedMB: mb))
        return [CleanupEngineResult(label: "Dotfile caches", freedMB: mb)]
    }

    // MARK: 18. Scattered Junk

    func cleanScatteredJunk(dryRun: Bool, cleanDSStore: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let localFM = FileManager.default
        let home = localFM.homeDirectoryForCurrentUser.path
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

    // MARK: 19. Orphaned Remnants

    func cleanOrphanedRemnants(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning orphaned remnants..."))
        var freed: Int64 = 0

        // Old iOS DeviceSupport
        let (f, item) = try await cleanContents(of: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", dryRun: dryRun, progress: progress)
        freed += f
        if dryRun { emitFileItem(item, category: "Orphaned remnants", parentName: nil, progress: progress) }

        // Detect orphaned app remnants
        let installedApps = collectInstalledApps()
        progress?(.log("  Found \(installedApps.count) installed applications"))

        let scanDirs = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/Library/Preferences",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Cookies",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Internet Plug-Ins",
            "/Users/Shared"
        ]

        var orphanCount = 0
        for scanDir in scanDirs {
            guard fm.fileExists(atPath: scanDir) else { continue }
            let entries = (try? fm.contentsOfDirectory(atPath: scanDir)) ?? []
            for entry in entries {
                // Skip Apple system entries
                if entry.hasPrefix("com.apple.") || entry.hasPrefix("group.com.apple.") {
                    continue
                }
                // Skip generic/system entries
                let lower = entry.lowercased()
                if ["caches", "logs", "preferences", "byhost", "metadata", "suggestions",
                    "cloudkit", "identityservices", "messages", "geoServices",
                    "mobile documents", "relocated items", "previously relocated items",
                    // Apple system frameworks and services
                    "animoji", "passkit", "gamekit", "gamecenter", "familycircle", "familycircled",
                    "knowledge", "spotlight", "music", "contactsd", "homeenergyd",
                    "networkserviceproxy", "mediaanalysisd", "duetexpertcenter",
                    "coresuggestions", "medialibrary", "imcore", "telephonyutilities",
                    "usereventagent", "applemusicservices", "pencilkit", "screentime",
                    "homekit", "healthkit", "storekit", "corelocation", "coremotion",
                    "corenfc", "carplay", "classkit", "shazamkit", "safariservices",
                    "linkpresentation", "intents", "assistant", "siri",
                    "contextstoreagent", "mobilemeaccounts", "loginwindow",
                    "diagnostics_agent", "mbuseragent"].contains(where: { lower.contains($0) }) {
                    continue
                }
                // Skip workflow/shortcuts entries
                if entry.hasPrefix("group.is.workflow.") || entry.hasPrefix("is.workflow.") {
                    continue
                }
                // Skip heavy containers (Docker, VMs) — virtual disks cause timeouts
                if Self.isHeavyContainer(entry) {
                    progress?(.log("  \(entry) — skipped (heavy container)"))
                    continue
                }

                if !isEntryInstalled(entry, installedApps: installedApps) {
                    let entryPath = "\(scanDir)/\(entry)"
                    let entrySize = await getDirectorySizeWithTimeout(entryPath, timeout: .seconds(5))
                    if entrySize > 1024 * 1024 { // > 1 MB
                        orphanCount += 1
                        let shortDir = scanDir.replacingOccurrences(of: home, with: "~")
                        if dryRun {
                            progress?(.log("  \(entry) — \(Self.formatBytes(entrySize)) [\(shortDir)]"))
                            freed += entrySize
                        } else {
                            try? fm.removeItem(atPath: entryPath)
                            progress?(.log("  Removed \(entry) — \(Self.formatBytes(entrySize))"))
                            freed += entrySize
                        }
                    }
                }
            }
        }
        progress?(.log("  Detected \(orphanCount) orphaned entries"))

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Orphaned remnants total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Orphaned remnants", freedMB: mb))
        return [CleanupEngineResult(label: "Orphaned remnants", freedMB: mb)]
    }

    /// Collects installed app bundle IDs and names for orphan detection
    private func collectInstalledApps() -> Set<String> {
        var apps = Set<String>()
        let searchPaths = ["/Applications", "\(fm.homeDirectoryForCurrentUser.path)/Applications", "/Applications/Setapp"]
        for basePath in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appPath = "\(basePath)/\(item)"
                // Get bundle ID
                if let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
                   let bundleID = bundle.bundleIdentifier {
                    apps.insert(bundleID.lowercased())
                    // Also add last component (e.g., "Xcode" from "com.apple.dt.Xcode")
                    let parts = bundleID.components(separatedBy: ".")
                    if let last = parts.last { apps.insert(last.lowercased()) }
                }
                // Get app name
                let appName = item.replacingOccurrences(of: ".app", with: "").lowercased()
                apps.insert(appName)
            }
        }
        return apps
    }

    /// Checks if an entry name matches any installed app
    private func isEntryInstalled(_ entry: String, installedApps: Set<String>) -> Bool {
        let lower = entry.lowercased()
        // Direct match
        if installedApps.contains(lower) { return true }
        // Check dot-separated components (e.g., "com.google.Chrome" -> "chrome")
        for part in lower.components(separatedBy: ".") where part.count >= 3 {
            if installedApps.contains(part) { return true }
        }
        // Substring match against app names
        for app in installedApps where app.count >= 3 {
            if lower.contains(app) || app.contains(lower) { return true }
        }
        // Vendor-specific checks (match bash script logic)
        // Microsoft/Office
        if lower.contains("microsoft") || lower.contains("office") {
            if installedApps.contains(where: { $0.contains("microsoft") || $0.contains("office") }) {
                return true
            }
        }
        // Adobe
        if lower.contains("adobe") {
            if installedApps.contains(where: { $0.contains("adobe") }) {
                return true
            }
        }
        // Google
        if lower.contains("google") {
            if installedApps.contains(where: { $0.contains("google") }) {
                return true
            }
        }
        // Homebrew
        if lower.contains("homebrew") {
            // Check if brew command exists
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            task.arguments = ["brew"]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return true
            }
        }
        return false
    }

    // MARK: 20. Orphaned Files

    func cleanOrphanedFiles(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning orphaned files..."))
        var freed: Int64 = 0
        let installedApps = collectInstalledApps()

        // Scan ~/Library/HTTPStorages for orphaned entries
        let httpStorages = "\(home)/Library/HTTPStorages"
        if fm.fileExists(atPath: httpStorages) {
            let entries = (try? fm.contentsOfDirectory(atPath: httpStorages)) ?? []
            for entry in entries {
                if entry.hasPrefix("com.apple.") { continue }
                if Self.isHeavyContainer(entry) {
                    progress?(.log("  \(entry) — skipped (heavy container)"))
                    continue
                }
                if !isEntryInstalled(entry, installedApps: installedApps) {
                    let entryPath = "\(httpStorages)/\(entry)"
                    let entrySize = await getDirectorySizeWithTimeout(entryPath, timeout: .seconds(5))
                    if entrySize > 1024 * 1024 {
                        if dryRun {
                            freed += entrySize
                            progress?(.log("  Orphaned HTTPStorage: \(entry) — \(Self.formatBytes(entrySize))"))
                        } else {
                            try? fm.removeItem(atPath: entryPath)
                            freed += entrySize
                        }
                    }
                }
            }
        }

        // Scan ~/Library/Cookies for orphaned entries (Phase 4 enhancement)
        let cookiesDir = "\(home)/Library/Cookies"
        if fm.fileExists(atPath: cookiesDir) {
            let entries = (try? fm.contentsOfDirectory(atPath: cookiesDir)) ?? []
            for entry in entries {
                if entry.hasPrefix("com.apple.") { continue }
                if !isEntryInstalled(entry, installedApps: installedApps) {
                    let entryPath = "\(cookiesDir)/\(entry)"
                    let entrySize = (try? fm.attributesOfItem(atPath: entryPath)[.size] as? Int64) ?? 0
                    if entrySize > 1024 * 1024 {
                        if dryRun {
                            freed += entrySize
                            progress?(.log("  Orphaned Cookie: \(entry) — \(Self.formatBytes(entrySize))"))
                        } else {
                            try? fm.removeItem(atPath: entryPath)
                            freed += entrySize
                        }
                    }
                }
            }
        }

        // Scan ~/Library/WebKit for orphaned entries
        let webkitDir = "\(home)/Library/WebKit"
        if fm.fileExists(atPath: webkitDir) {
            let entries = (try? fm.contentsOfDirectory(atPath: webkitDir)) ?? []
            for entry in entries {
                if entry.hasPrefix("com.apple.") { continue }
                if Self.isHeavyContainer(entry) {
                    progress?(.log("  \(entry) — skipped (heavy container)"))
                    continue
                }
                if !isEntryInstalled(entry, installedApps: installedApps) {
                    let entryPath = "\(webkitDir)/\(entry)"
                    let entrySize = await getDirectorySizeWithTimeout(entryPath, timeout: .seconds(5))
                    if entrySize > 1024 * 1024 {
                        if dryRun {
                            freed += entrySize
                            progress?(.log("  Orphaned WebKit: \(entry) — \(Self.formatBytes(entrySize))"))
                        } else {
                            try? fm.removeItem(atPath: entryPath)
                            freed += entrySize
                        }
                    }
                }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Orphaned files total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Orphaned files", freedMB: mb))
        return [CleanupEngineResult(label: "Orphaned files", freedMB: mb)]
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning large files..."))
        var totalFound: Int64 = 0
        var items: [(String, Int64)] = []

        // Old DMG installers in Downloads, Desktop, Documents
        let downloadDirs = ["\(home)/Downloads", "\(home)/Desktop", "\(home)/Documents"]
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        for downloadDir in downloadDirs {
            guard fm.fileExists(atPath: downloadDir) else { continue }
            let contents = try? fm.contentsOfDirectory(atPath: downloadDir)
            var scannedCount = 0
            for file in (contents ?? []) {
                let ext = (file as NSString).pathExtension.lowercased()
                if ["dmg", "pkg", "iso", "zip"].contains(ext) {
                    let filePath = "\(downloadDir)/\(file)"
                    if let attrs = try? fm.attributesOfItem(atPath: filePath),
                       let modDate = attrs[.modificationDate] as? Date,
                       modDate < cutoffDate,
                       let size = attrs[.size] as? Int64, size > 100 * 1024 * 1024 {
                        items.append(("\(downloadDir.replacingOccurrences(of: home, with: "~"))/\(file)", size))
                        totalFound += size
                        if dryRun {
                            emitFileItem(CleanupFileItem(path: filePath, sizeBytes: size, modificationDate: modDate, isDirectory: false), category: "Large files", parentName: nil, progress: progress)
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
                        progress?(.log("  Skipping heavy directory: \(Self.shortPath(fullPath))"))
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
                            emitFileItem(CleanupFileItem(path: fullPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Large files", parentName: nil, progress: progress)
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
                            emitFileItem(CleanupFileItem(path: fullPath, sizeBytes: size, modificationDate: nil, isDirectory: false), category: "Large files", parentName: nil, progress: progress)
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
        progress?(.log("Large files total: \(Self.formatBytes(totalFound))"))
        progress?(.result(label: "Large files", freedMB: mb))
        return [CleanupEngineResult(label: "Large files", freedMB: mb)]
    }

    // MARK: 22. Dynamic Cache Discovery

    func cleanDynamicCacheDiscovery(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
                    emitFileItem(CleanupFileItem(path: entryPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Dynamic cache discovery", parentName: "Review manually", progress: progress)
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

        let result = try? await commandRunner.run(command: "/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])
        let output = result?.stdout ?? ""

        let snapshots = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.contains("com.apple.TimeMachine") }

        progress?(.log("  Found \(snapshots.count) local snapshots"))

        if dryRun {
            for snap in snapshots {
                progress?(.log("  ⊘ \(snap)"))
            }
            progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
            return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
        }

        var deleted = 0
        for snap in snapshots {
            try Task.checkCancellation()
            _ = try? await commandRunner.run(command: "/usr/bin/tmutil", arguments: ["deletelocalsnapshots", snap])
            deleted += 1
            progress?(.log("  ✓ Deleted \(snap)"))
        }

        progress?(.log("  Deleted \(deleted) snapshots"))
        progress?(.result(label: "Time Machine Snapshots", freedMB: 0))
        return [CleanupEngineResult(label: "Time Machine Snapshots", freedMB: 0)]
    }

    // MARK: 24. iOS Backups

    func cleanIOSBackups(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning iOS backups..."))

        let backupDir = "\(home)/Library/Application Support/MobileSync/Backup"
        let (freed, item) = try await cleanContents(of: backupDir, dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "iOS Backups", parentName: nil, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "iOS Backups", freedMB: mb))
        return [CleanupEngineResult(label: "iOS Backups", freedMB: mb)]
    }

    // MARK: 25. Mail Downloads

    func cleanMailDownloads(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning saved application state..."))

        let (freed, item) = try await cleanContents(of: "\(home)/Library/Saved Application State", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Saved Application State", parentName: nil, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Saved Application State", freedMB: mb))
        return [CleanupEngineResult(label: "Saved Application State", freedMB: mb)]
    }

    // MARK: 27. Crash Reporter

    func cleanCrashReporter(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
                progress?(.log("  \(Self.shortPath(systemPath)) — protected, skipped"))
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Crash Reporter", freedMB: mb))
        return [CleanupEngineResult(label: "Crash Reporter", freedMB: mb)]
    }

    // MARK: 28. AssetsV2 / iWork Templates

    func cleanAssetsV2(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning AssetsV2 / iWork templates..."))

        let (freed, item) = try await cleanContents(of: "\(home)/Library/Application Support/AssetsV2", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "AssetsV2 / iWork Templates", parentName: nil, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "AssetsV2 / iWork Templates", freedMB: mb))
        return [CleanupEngineResult(label: "AssetsV2 / iWork Templates", freedMB: mb)]
    }

    // MARK: 29. CloudKit Cache

    func cleanCloudKitCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning CloudKit cache..."))

        let (freed, item) = try await cleanContents(of: "\(home)/Library/Caches/CloudKit", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "CloudKit Cache", parentName: nil, progress: progress) }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "CloudKit Cache", freedMB: mb))
        return [CleanupEngineResult(label: "CloudKit Cache", freedMB: mb)]
    }

    // MARK: 30. Swift Package Manager Cache

    func cleanSwiftPMCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning Microsoft Teams cache..."))
        var freed: Int64 = 0

        let teamsSubdirs = [
            "Cache", "Code Cache", "GPUCache", "IndexedDB",
            "Blob_storage", "Service Worker", "Session Storage",
            "Local Storage", "tmp"
        ]

        // Teams v1 (classic) paths
        let teamsV1Base = "\(home)/Library/Application Support/Microsoft/Teams"
        // Teams v2 (new) paths
        let teamsV2Base = "\(home)/Library/Application Support/Microsoft/Teams2"
        // Group Container (Teams v2 may store data here)
        let teamsGroupContainer = "\(home)/Library/Group Containers/UBF8T346G9.com.microsoft.teams"

        let allTeamsBases = [teamsV1Base, teamsV2Base, teamsGroupContainer]

        for teamsBase in allTeamsBases {
            guard fm.fileExists(atPath: teamsBase) else { continue }
            progress?(.log("  Found: \(Self.shortPath(teamsBase))"))

            for sub in teamsSubdirs {
                let path = "\(teamsBase)/\(sub)"
                let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Microsoft Teams Cache", parentName: nil, progress: progress) }
            }
        }

        // Teams v2 may also store data in Caches directory
        let teamsV2CachePaths = [
            "\(home)/Library/Caches/com.microsoft.teams2",
            "\(home)/Library/Caches/com.microsoft.teams"
        ]
        for cachePath in teamsV2CachePaths {
            let (f, item) = try await cleanContents(of: cachePath, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Microsoft Teams Cache", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("  Microsoft Teams total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Microsoft Teams Cache", freedMB: mb))
        return [CleanupEngineResult(label: "Microsoft Teams Cache", freedMB: mb)]
    }

    // MARK: 34. Adobe Caches

    func cleanAdobeCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning Chrome extra caches..."))
        var freed: Int64 = 0

        let chromeBase = "\(home)/Library/Application Support/Google/Chrome/Default"
        let chromeBaseRoot = "\(home)/Library/Application Support/Google/Chrome"
        let subdirs = ["Cache", "Code Cache", "GPUCache", "Service Worker", "Session Storage"]
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning user LaunchAgents..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/LaunchAgents", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Launch Agents", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Launch Agents", freedMB: mb))
        return [CleanupEngineResult(label: "Launch Agents", freedMB: mb)]
    }

    // MARK: 37. Launch Daemons (system)

    func cleanLaunchDaemons(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Scanning Launch Daemons (system)..."))
        progress?(.log("  Requires Full Disk Access — skipped in scan"))
        if !dryRun {
            let (freed, _) = try await cleanContents(of: "/Library/LaunchDaemons", dryRun: false, progress: progress)
            let mb = Int(freed / (1024 * 1024))
            progress?(.result(label: "Launch Daemons", freedMB: mb))
            return [CleanupEngineResult(label: "Launch Daemons", freedMB: mb)]
        }
        return [CleanupEngineResult(label: "Launch Daemons", freedMB: 0)]
    }

    // MARK: 38. Privileged Helper Tools

    func cleanPrivilegedHelpers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        progress?(.log("Scanning Privileged Helper Tools..."))
        progress?(.log("  Requires Full Disk Access — skipped in scan"))
        if !dryRun {
            let (freed, _) = try await cleanContents(of: "/Library/PrivilegedHelperTools", dryRun: false, progress: progress)
            let mb = Int(freed / (1024 * 1024))
            progress?(.result(label: "Privileged Helper Tools", freedMB: mb))
            return [CleanupEngineResult(label: "Privileged Helper Tools", freedMB: mb)]
        }
        return [CleanupEngineResult(label: "Privileged Helper Tools", freedMB: 0)]
    }

    // MARK: 39. Package Receipts

    func cleanPkgReceipts(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning shared file lists..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/Application Support/com.apple.sharedfilelist", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Shared File Lists", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Shared File Lists", freedMB: mb))
        return [CleanupEngineResult(label: "Shared File Lists", freedMB: mb)]
    }

    // MARK: 42. Cloud Docs

    func cleanCloudDocs(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning CloudDocs..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/Application Support/CloudDocs", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Cloud Docs", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Cloud Docs", freedMB: mb))
        return [CleanupEngineResult(label: "Cloud Docs", freedMB: mb)]
    }

    // MARK: 43. Photos Cache

    func cleanPhotosCache(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning Photos cache..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/Containers/com.apple.Photos/Data/Library/Caches", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Photos Cache", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Photos Cache", freedMB: mb))
        return [CleanupEngineResult(label: "Photos Cache", freedMB: mb)]
    }

    // MARK: 44. Voice Memos

    func cleanVoiceMemos(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning Voice Memos..."))
        let (freed, item) = try await cleanContents(of: "\(home)/Library/Application Support/com.apple.VoiceMemos/Recordings", dryRun: dryRun, progress: progress)
        if dryRun { emitFileItem(item, category: "Voice Memos", parentName: nil, progress: progress) }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Voice Memos", freedMB: mb))
        return [CleanupEngineResult(label: "Voice Memos", freedMB: mb)]
    }

    // MARK: 45. GarageBand / Logic Pro

    func cleanGarageBandLogic(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
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
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning old backups..."))
        var freed: Int64 = 0
        let paths = [
            "\(home)/Backups",
        ]
        for path in paths {
            let (f, item) = try await cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Old Backups", parentName: nil, progress: progress) }
        }
        // Find *.backup files
        let backupDirs = ["\(home)/Desktop", "\(home)/Documents", "\(home)/Downloads"]
        for dir in backupDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            let contents = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for file in contents where file.hasSuffix(".backup") {
                let filePath = "\(dir)/\(file)"
                let (f, item) = try await removeFile(filePath, dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Old Backups", parentName: nil, progress: progress) }
            }
        }
        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Old Backups", freedMB: mb))
        return [CleanupEngineResult(label: "Old Backups", freedMB: mb)]
    }

    // MARK: 49. DNS Flush

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

        let appPaths = ["/Applications", "\(fm.homeDirectoryForCurrentUser.path)/Applications", "/Applications/Setapp"]
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
                progress?(.log("  \(name) — last used: \(dateStr) [\(Self.shortPath(path))]"))
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


