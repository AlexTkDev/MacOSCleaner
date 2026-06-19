import Foundation
import OSLog

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

    public init(fast: Duration = .seconds(30), system: Duration = .seconds(120), full: Duration = .seconds(300)) {
        self.fast = fast
        self.system = system
        self.full = full
    }

    public static let `default` = CleanupTimeouts()
}

// MARK: - Engine Events

/// Events emitted by CleanupEngine for UI.
public enum CleanupEngineEvent: Sendable {
    case step(current: Int, total: Int, title: String)
    case result(label: String, freedMB: Int)
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

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        safetyManager: SafetyManager = SafetyManager(),
        timeouts: CleanupTimeouts = .default
    ) {
        self.commandRunner = commandRunner
        self.safetyManager = safetyManager
        self.timeouts = timeouts
    }

    // MARK: - Public Interface

    /// Runs cleanup for the specified categories.
    public func run(
        categories: [CleanupCategory],
        dryRun: Bool = false,
        progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil
    ) async throws -> [CleanupEngineResult] {
        var results: [CleanupEngineResult] = []
        let total = categories.count

        for (index, category) in categories.enumerated() {
            try Task.checkCancellation()

            let stepTitle = Self.titleForCategory(category)
            progress?(.step(current: index + 1, total: total, title: stepTitle))

            let categoryResults: [CleanupEngineResult]
            switch category {
            case .appCaches:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanAppCaches(dryRun: dryRun, progress: progress)
                }
            case .packageManagers:
                categoryResults = try await withTimeout(timeouts.system) {
                    try await self.cleanPackageManagers(dryRun: dryRun, progress: progress)
                }
            case .gradleMaven:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanGradleMaven(dryRun: dryRun, progress: progress)
                }
            case .flutterDart:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanFlutterDart(dryRun: dryRun, progress: progress)
                }
            case .xcode:
                categoryResults = try await withTimeout(timeouts.full) {
                    try await self.cleanXcode(dryRun: dryRun, progress: progress)
                }
            case .iosSimulators:
                categoryResults = try await withTimeout(timeouts.full) {
                    try await self.cleanIOSSimulators(dryRun: dryRun, progress: progress)
                }
            case .androidCaches:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanAndroidCaches(dryRun: dryRun, progress: progress)
                }
            case .androidSDK:
                categoryResults = try await withTimeout(timeouts.system) {
                    try await self.cleanAndroidSDK(dryRun: dryRun, progress: progress)
                }
            case .ideCaches:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanIDECaches(dryRun: dryRun, progress: progress)
                }
            case .browserCaches:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanBrowserCaches(dryRun: dryRun, progress: progress)
                }
            case .messagingMedia:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanMessagingMedia(dryRun: dryRun, progress: progress)
                }
            case .docker:
                categoryResults = try await withTimeout(timeouts.system) {
                    try await self.cleanDocker(dryRun: dryRun, progress: progress)
                }
            case .languageCaches:
                categoryResults = try await withTimeout(timeouts.system) {
                    try await self.cleanLanguageCaches(dryRun: dryRun, progress: progress)
                }
            case .userLogs:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanUserLogs(dryRun: dryRun, progress: progress)
                }
            case .systemCaches:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanSystemCaches(dryRun: dryRun, progress: progress)
                }
            case .appContainers:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanAppContainers(dryRun: dryRun, progress: progress)
                }
            case .dotfileCaches:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanDotfileCaches(dryRun: dryRun, progress: progress)
                }
            case .scatteredJunk:
                categoryResults = try await withTimeout(timeouts.full) {
                    try await self.cleanScatteredJunk(dryRun: dryRun, progress: progress)
                }
            case .orphanedRemnants:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanOrphanedRemnants(dryRun: dryRun, progress: progress)
                }
            case .orphanedFiles:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanOrphanedFiles(dryRun: dryRun, progress: progress)
                }
            case .largeFiles:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanLargeFiles(dryRun: dryRun, progress: progress)
                }
            case .dynamicCacheDiscovery:
                categoryResults = try await withTimeout(timeouts.fast) {
                    try await self.cleanDynamicCacheDiscovery(dryRun: dryRun, progress: progress)
                }
            }
            results.append(contentsOf: categoryResults)
        }

        return results
    }

    /// Scans the specified categories without deletion.
    public func scan(
        categories: [CleanupCategory],
        progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil
    ) async throws -> [CleanupEngineResult] {
        return try await run(categories: categories, dryRun: true, progress: progress)
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

    // MARK: - Category Titles

    private static func titleForCategory(_ category: CleanupCategory) -> String {
        switch category {
        case .appCaches: return "User app caches"
        case .packageManagers: return "Package managers"
        case .gradleMaven: return "Gradle + Maven"
        case .flutterDart: return "Flutter / Dart"
        case .xcode: return "Xcode"
        case .iosSimulators: return "iOS Simulators"
        case .androidCaches: return "Android caches"
        case .androidSDK: return "Android SDK"
        case .ideCaches: return "IDE / Electron caches"
        case .browserCaches: return "Browser caches"
        case .messagingMedia: return "Messaging / media"
        case .docker: return "Docker"
        case .languageCaches: return "Language caches"
        case .userLogs: return "User logs"
        case .systemCaches: return "System caches"
        case .appContainers: return "App containers"
        case .dotfileCaches: return "Dotfile caches"
        case .scatteredJunk: return "Scattered junk"
        case .orphanedRemnants: return "Orphaned remnants"
        case .orphanedFiles: return "Orphaned files"
        case .largeFiles: return "Large files"
        case .dynamicCacheDiscovery: return "Dynamic cache discovery"
        }
    }
}

// MARK: - Cleanup Options

/// Options controlling which categories are cleaned.
public struct CleanupOptions: Sendable, Equatable {
    /// When true, includes .DS_Store and other scattered junk files.
    public var cleanDSStore: Bool = false

    public init(cleanDSStore: Bool = false) {
        self.cleanDSStore = cleanDSStore
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
        ]

        if cleanDSStore {
            categories.append(.scatteredJunk)
        }

        return categories
    }
}

// MARK: - CleanupEngineError

public enum CleanupEngineError: Error, LocalizedError {
    case timeout
    case safetyViolation(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .timeout: return "Operation timed out"
        case .safetyViolation(let path): return "Safety violation: \(path)"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        }
    }
}

// MARK: - Logging Helpers

extension CleanupEngine {

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    }

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
    }
}

// MARK: - FileManager Helpers

extension CleanupEngine {

    private func fileItemForPath(_ path: String) -> CleanupFileItem? {
        let attrs = try? fm.attributesOfItem(atPath: path)
        let modDate = attrs?[.modificationDate] as? Date
        let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
        let size: Int64
        if isDir {
            size = (try? getDirectorySize(path)) ?? 0
        } else {
            size = (attrs?[.size] as? Int64) ?? 0
        }
        return CleanupFileItem(path: path, sizeBytes: size, modificationDate: modDate, isDirectory: isDir)
    }

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

    /// Safely cleans directory contents (the directory itself is preserved).
    /// Returns (freed bytes, file item for dryRun preview).
    func cleanContents(of path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) throws -> (freed: Int64, item: CleanupFileItem?) {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let before = try getDirectorySize(path)
        let sizeStr = Self.formatBytes(before)

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(sizeStr)"))
            let item = fileItemForPath(path)
            return (before, item)
        }

        let contents = try fm.contentsOfDirectory(atPath: path)
        var removedCount = 0
        for item in contents {
            let itemURL = url.appendingPathComponent(item)
            try? fm.removeItem(at: itemURL)
            removedCount += 1
        }

        let after = try getDirectorySize(path)
        let freed = max(0, before - after)
        if freed > 0 {
            progress?(.log("  \(Self.shortPath(path)) — removed \(removedCount) items, freed \(Self.formatBytes(freed))"))
        }
        return (freed, nil)
    }

    /// Removes an entire directory.
    /// Returns (freed bytes, file item for dryRun preview).
    func removeDirectory(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) throws -> (freed: Int64, item: CleanupFileItem?) {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let before = try getDirectorySize(path)

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(before))"))
            let item = fileItemForPath(path)
            return (before, item)
        }

        try? fm.removeItem(atPath: path)
        progress?(.log("  \(Self.shortPath(path)) — removed, freed \(Self.formatBytes(before))"))
        return (before, nil)
    }

    /// Removes a file.
    /// Returns (freed bytes, file item for dryRun preview).
    func removeFile(_ path: String, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) throws -> (freed: Int64, item: CleanupFileItem?) {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let attrs = try fm.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int64) ?? 0

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(Self.formatBytes(size))"))
            let modDate = attrs[.modificationDate] as? Date
            let item = CleanupFileItem(path: path, sizeBytes: size, modificationDate: modDate, isDirectory: false)
            return (size, item)
        }

        try? fm.removeItem(atPath: path)
        progress?(.log("  \(Self.shortPath(path)) — removed, freed \(Self.formatBytes(size))"))
        return (size, nil)
    }

    /// Returns directory size in bytes.
    func getDirectorySize(_ path: String) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        return fm.getDirectorySize(url: url)
    }

    /// Wraps a command string to source the user's shell profile first,
    /// ensuring tools installed via nvm, volta, rbenv, etc. are on PATH.
    /// Supports zsh, bash, fish, and nushell.
    private func withUserPath(_ command: String) -> String {
        let home = fm.homeDirectoryForCurrentUser.path
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shellPath as NSString).lastPathComponent
        
        switch shellName {
        case "fish":
            return """
            fish -c 'source "\(home)/.config/fish/config.fish" 2>/dev/null; \(command.replacingOccurrences(of: "'", with: "\\'"))'
            """
        case "nushell", "nu":
            return """
            nu -c 'source "\(home)/.config/nushell/env.nu" 2>/dev/null; source "\(home)/.config/nushell/config.nu" 2>/dev/null; \(command.replacingOccurrences(of: "'", with: "\\'"))'
            """
        case "bash":
            return """
            if [ -f "\(home)/.bash_profile" ]; then source "\(home)/.bash_profile" 2>/dev/null; \
            elif [ -f "\(home)/.bashrc" ]; then source "\(home)/.bashrc" 2>/dev/null; fi; \
            \(command)
            """
        default:
            // Default to zsh (most common on macOS)
            return """
            if [ -f "\(home)/.zshrc" ]; then source "\(home)/.zshrc" 2>/dev/null; \
            elif [ -f "\(home)/.zprofile" ]; then source "\(home)/.zprofile" 2>/dev/null; \
            elif [ -f "\(home)/.bash_profile" ]; then source "\(home)/.bash_profile" 2>/dev/null; \
            elif [ -f "\(home)/.bashrc" ]; then source "\(home)/.bashrc" 2>/dev/null; fi; \
            \(command)
            """
        }
    }

    /// Returns true if the command is available in the system.
    func commandExists(_ command: String) -> Bool {
        // Check common executable paths including nvm, volta, rbenv, etc.
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "\(home)/.nvm/versions/node",
            "\(home)/.volta/bin/\(command)",
            "\(home)/.rbenv/shims/\(command)",
            "\(home)/.pyenv/shims/\(command)",
            "\(home)/.cargo/bin/\(command)",
            "\(home)/.bun/bin/\(command)",
            "\(home)/go/bin/\(command)"
        ]

        for candidate in candidates {
            var isDir: ObjCBool = false
            if candidate.hasSuffix("/node") {
                // nvm: scan node version directories for the command
                if fm.fileExists(atPath: candidate, isDirectory: &isDir) && isDir.boolValue {
                    if let versions = try? fm.contentsOfDirectory(atPath: candidate) {
                        for ver in versions {
                            if fm.fileExists(atPath: "\(candidate)/\(ver)/bin/\(command)") {
                                return true
                            }
                        }
                    }
                }
            } else if fm.fileExists(atPath: candidate, isDirectory: &isDir) && !isDir.boolValue {
                return true
            }
        }
        return false
    }

    /// Removes old files (older than N days) from a directory.
    /// Returns (freed bytes, file item for dryRun preview).
    func cleanOldFiles(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) throws -> (freed: Int64, item: CleanupFileItem?) {
        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var freed: Int64 = 0
        var removedCount = 0

        let contents = try fm.contentsOfDirectory(atPath: path)
        for item in contents {
            let itemURL = URL(fileURLWithPath: path).appendingPathComponent(item)
            let attrs = try? fm.attributesOfItem(atPath: itemURL.path)
            if let modDate = attrs?[.modificationDate] as? Date, modDate < cutoffDate {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: itemURL.path, isDirectory: &isDir)
                let size: Int64
                if isDir.boolValue {
                    size = try getDirectorySize(itemURL.path)
                } else {
                    size = (attrs?[.size] as? Int64) ?? 0
                }
                if !dryRun {
                    try? fm.removeItem(at: itemURL)
                }
                freed += size
                removedCount += 1
            }
        }
        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(removedCount) items older than \(days) days (\(Self.formatBytes(freed)))"))
            let item = fileItemForPath(path)
            return (freed, item)
        } else {
            progress?(.log("  \(Self.shortPath(path)) — removed \(removedCount) old items, freed \(Self.formatBytes(freed))"))
        }
        return (freed, nil)
    }

    /// Recursively removes old files (older than N days) from a directory and all subdirectories.
    /// Returns (freed bytes, file item for dryRun preview).
    func cleanOldFilesRecursive(in path: String, olderThanDays days: Int, dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)? = nil) throws -> (freed: Int64, item: CleanupFileItem?) {
        guard fm.fileExists(atPath: path) else {
            progress?(.log("  \(Self.shortPath(path)) — not found, skipped"))
            return (0, nil)
        }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var freed: Int64 = 0
        var removedCount = 0

        guard let enumerator = fm.enumerator(atPath: path) else { return (0, nil) }
        while let item = enumerator.nextObject() as? String {
            try Task.checkCancellation()
            let itemPath = "\(path)/\(item)"
            let attrs = try? fm.attributesOfItem(atPath: itemPath)
            if let modDate = attrs?[.modificationDate] as? Date, modDate < cutoffDate {
                let size = (attrs?[.size] as? Int64) ?? 0
                if !dryRun { try? fm.removeItem(atPath: itemPath) }
                freed += size
                removedCount += 1
            }
        }

        if dryRun {
            progress?(.log("  \(Self.shortPath(path)) — \(removedCount) items older than \(days) days (\(Self.formatBytes(freed)))"))
            let item = fileItemForPath(path)
            return (freed, item)
        } else {
            progress?(.log("  \(Self.shortPath(path)) — removed \(removedCount) old items, freed \(Self.formatBytes(freed))"))
        }
        return (freed, nil)
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
            "\(home)/Library/Caches/JetBrains"
        ]

        var totalFreed: Int64 = 0
        for dir in cacheDirs {
            try Task.checkCancellation()
            let (freed, item) = try cleanContents(of: dir, dryRun: dryRun, progress: progress)
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
            let (freed, item) = try removeFile(plist, dryRun: dryRun, progress: progress)
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
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.log("  Homebrew cache: \(Self.formatBytes(try getDirectorySize(cacheDir)))"))
                progress?(.result(label: "Homebrew cache", freedMB: size))
                results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: size))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: try getDirectorySize(cacheDir), modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = try getDirectorySize(cacheDir)
                progress?(.log("  Running: brew cleanup --prune=all -q"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("brew cleanup --prune=all -q")])
                let after = try getDirectorySize(cacheDir)
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
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.log("  npm cache: \(Self.formatBytes(try getDirectorySize(cacheDir)))"))
                progress?(.result(label: "npm cache", freedMB: size))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: size))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: try getDirectorySize(cacheDir), modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = try getDirectorySize(cacheDir)
                progress?(.log("  Running: npm cache clean --force"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("npm cache clean --force 2>/dev/null")])
                let after = try getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
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
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.log("  yarn cache: \(Self.formatBytes(try getDirectorySize(cacheDir)))"))
                progress?(.result(label: "yarn cache", freedMB: size))
                results.append(CleanupEngineResult(label: "yarn cache", freedMB: size))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: try getDirectorySize(cacheDir), modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = try getDirectorySize(cacheDir)
                progress?(.log("  Running: yarn cache clean"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("yarn cache clean 2>/dev/null")])
                let after = try getDirectorySize(cacheDir)
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
                let size = Int(try getDirectorySize(storeDir) / (1024 * 1024))
                progress?(.log("  pnpm store: \(Self.formatBytes(try getDirectorySize(storeDir)))"))
                progress?(.result(label: "pnpm store", freedMB: size))
                results.append(CleanupEngineResult(label: "pnpm store", freedMB: size))
                emitFileItem(CleanupFileItem(path: storeDir, sizeBytes: try getDirectorySize(storeDir), modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = try getDirectorySize(storeDir)
                progress?(.log("  Running: pnpm store prune"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("pnpm store prune 2>/dev/null")])
                let after = try getDirectorySize(storeDir)
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
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.log("  CocoaPods cache: \(Self.formatBytes(try getDirectorySize(cacheDir)))"))
                progress?(.result(label: "CocoaPods cache", freedMB: size))
                results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: size))
                emitFileItem(CleanupFileItem(path: cacheDir, sizeBytes: try getDirectorySize(cacheDir), modificationDate: nil, isDirectory: true), category: "Package managers", parentName: nil, progress: progress)
            } else {
                let before = try getDirectorySize(cacheDir)
                progress?(.log("  Running: pod cache clean --all"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("pod cache clean --all 2>/dev/null")])
                let after = try getDirectorySize(cacheDir)
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

    func cleanGradleMaven(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning Gradle + Maven caches..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/.gradle/caches",
            "\(home)/.gradle/wrapper/dists",
            "\(home)/.gradle/daemon",
            "\(home)/.gradle/buildOutputCleanup",
            "\(home)/.kotlin",
            "\(home)/.m2/repository",
        ]
        for path in paths {
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Gradle + Maven", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Gradle + Maven total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Gradle caches + wrapper + daemon", freedMB: mb))
        return [CleanupEngineResult(label: "Gradle + Maven", freedMB: mb)]
    }

    // MARK: 4. Flutter / Dart

    func cleanFlutterDart(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning Flutter / Dart caches..."))
        var freed: Int64 = 0

        let paths = [
            "\(home)/.pub-cache/hosted",
            "\(home)/.pub-cache/git",
            "\(home)/.dartServer"
        ]
        for path in paths {
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Flutter / Dart", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Flutter / Dart total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Dart/Flutter package caches", freedMB: mb))
        return [CleanupEngineResult(label: "Flutter / Dart", freedMB: mb)]
    }

    // MARK: 5. Xcode

    func cleanXcode(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
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
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Xcode", parentName: nil, progress: progress) }
        }
        let (af, ai) = try cleanOldFiles(in: "\(home)/Library/Developer/Xcode/Archives", olderThanDays: 90, dryRun: dryRun, progress: progress)
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

        let (cf, ci) = try cleanContents(of: "\(home)/Library/Developer/CoreSimulator/Caches", dryRun: dryRun, progress: progress)
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
                let (f1, i1) = try cleanContents(of: cachesPath, dryRun: dryRun, progress: progress)
                freed += f1
                if dryRun { emitFileItem(i1, category: "iOS Simulators", parentName: nil, progress: progress) }
                let (f2, i2) = try cleanContents(of: tmpPath, dryRun: dryRun, progress: progress)
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
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Android caches", parentName: nil, progress: progress) }
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
                let (f, item) = try removeDirectory(dir, dryRun: dryRun, progress: progress)
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
                let (f, item) = try removeDirectory(dir, dryRun: dryRun, progress: progress)
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
            // Sublime Text
            "\(home)/Library/Caches/com.sublimetext.4",
            "\(home)/Library/Caches/com.sublimetext.3",
            // Arc Browser
            "\(home)/Library/Caches/company.thebrowser.Browser",
            // Vivaldi
            "\(home)/Library/Caches/com.vivaldi.Vivaldi",
        ]

        progress?(.log("Scanning IDE / Electron caches (\(ideDirs.count) paths)..."))
        var totalFreed: Int64 = 0
        for dir in ideDirs {
            try Task.checkCancellation()
            let (freed, item) = try cleanContents(of: dir, dryRun: dryRun, progress: progress)
            totalFreed += freed
            if dryRun { emitFileItem(item, category: "IDE / Electron caches", parentName: nil, progress: progress) }
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.log("IDE / Electron total: \(Self.formatBytes(totalFreed))"))
        progress?(.result(label: "IDE / Electron caches", freedMB: mb))
        return [CleanupEngineResult(label: "IDE / Electron caches", freedMB: mb)]
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
            let (freed, item) = try cleanContents(of: dir, dryRun: dryRun, progress: progress)
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
            "\(home)/Library/Caches/us.zoom.xos",
            "\(home)/Library/Messages/Attachments",
            "\(home)/Library/Caches/com.signal.Signal",
            "\(home)/Library/Caches/com.tencent.xinWeChat",
            "\(home)/Library/Caches/com.microsoft.teams2",
        ]

        var totalFreed: Int64 = 0
        for dir in dirs {
            try Task.checkCancellation()
            let (freed, item) = try cleanContents(of: dir, dryRun: dryRun, progress: progress)
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
        guard await commandRunner.commandExists("docker") else {
            progress?(.log("Docker not found, skipped"))
            return [CleanupEngineResult(label: "Docker", freedMB: 0)]
        }

        progress?(.log("Checking Docker disk usage..."))
        let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "docker system df --format '{{.Reclaimable}}' 2>/dev/null"])
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
                let dockerRoot = "/var/lib/docker"
                emitFileItem(CleanupFileItem(path: dockerRoot, sizeBytes: Int64(totalReclaimableMB) * 1024 * 1024, modificationDate: nil, isDirectory: true), category: "Docker", parentName: nil, progress: progress)
            } else {
                progress?(.log("  Nothing reclaimable"))
                progress?(.log("Docker: nothing reclaimable"))
            }
            return [CleanupEngineResult(label: "Docker", freedMB: totalReclaimableMB)]
        } else {
            progress?(.log("  Running: docker system prune -af --volumes"))
            _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "docker system prune -af --volumes 2>/dev/null"])
            progress?(.log("  Docker: freed ~\(totalReclaimableMB) MB"))
            progress?(.result(label: "Docker cleanup", freedMB: totalReclaimableMB))
            return [CleanupEngineResult(label: "Docker", freedMB: totalReclaimableMB)]
        }
    }

    // MARK: 13. Language Caches

    func cleanLanguageCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
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
            "\(home)/.m2/repository",
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
        ]
        for path in cachePaths {
            guard fm.fileExists(atPath: path) else { continue }
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Language caches", parentName: nil, progress: progress) }
        }

        // Ruby
        let gemRubyPath = "\(home)/.gem/ruby"
        if fm.fileExists(atPath: gemRubyPath) {
            let versions = try? fm.contentsOfDirectory(atPath: gemRubyPath)
            progress?(.log("  Ruby gems: \(versions?.count ?? 0) versions found"))
            for ver in (versions ?? []) {
                let (f, item) = try cleanContents(of: "\(gemRubyPath)/\(ver)/cache", dryRun: dryRun, progress: progress)
                freed += f
                if dryRun { emitFileItem(item, category: "Language caches", parentName: nil, progress: progress) }
            }
        }
        let (bundleF, bundleItem) = try cleanContents(of: "\(home)/.bundle/cache", dryRun: dryRun, progress: progress)
        freed += bundleF
        if dryRun { emitFileItem(bundleItem, category: "Language caches", parentName: nil, progress: progress) }

        // Go (build cache via command)
        if await commandRunner.commandExists("go") {
            progress?(.log("  Go runtime detected"))
            if dryRun {
                let goCachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go env GOCACHE 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let cachePath = goCachePath ?? "\(home)/Library/Caches/go-build"
                progress?(.log("  Go build cache: \(Self.shortPath(cachePath))"))
                let size = try getDirectorySize(cachePath)
                freed += size
                emitFileItem(CleanupFileItem(path: cachePath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Language caches", parentName: nil, progress: progress)
            } else {
                progress?(.log("  Running: go clean -cache"))
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go clean -cache 2>/dev/null")])
            }
        }

        // Go module cache
        if await commandRunner.commandExists("go") {
            let goModCache = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", withUserPath("go env GOMODCACHE 2>/dev/null")]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let modPath = goModCache ?? "\(home)/go/pkg/mod"
            progress?(.log("  Go module cache: \(Self.shortPath(modPath))"))
            let (f, item) = try cleanContents(of: modPath, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Language caches", parentName: nil, progress: progress) }
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
        let (lf, li) = try cleanOldFilesRecursive(in: "\(home)/Library/Logs", olderThanDays: 7, dryRun: dryRun, progress: progress)
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
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
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
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
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
                let dataCaches = "\(containersPath)/\(container)/Data/Library/Caches"
                if fm.fileExists(atPath: dataCaches) {
                    scannedCount += 1
                    let (f, item) = try cleanContents(of: dataCaches, dryRun: dryRun, progress: progress)
                    freed += f
                    if dryRun { emitFileItem(item, category: "App containers", parentName: nil, progress: progress) }
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
            let (f, item) = try cleanContents(of: path, dryRun: dryRun, progress: progress)
            freed += f
            if dryRun { emitFileItem(item, category: "Dotfile caches", parentName: nil, progress: progress) }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Dotfile caches total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Dotfile caches", freedMB: mb))
        return [CleanupEngineResult(label: "Dotfile caches", freedMB: mb)]
    }

    // MARK: 18. Scattered Junk

    func cleanScatteredJunk(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning scattered junk..."))
        var freed: Int64 = 0

        // Recursive .DS_Store removal
        let dsStoreDirs = [home, "/Applications"]
        for dir in dsStoreDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            guard let enumerator = fm.enumerator(atPath: dir) else { continue }
            while let item = enumerator.nextObject() as? String {
                try Task.checkCancellation()
                let fullPath = "\(dir)/\(item)"
                let fileName = (item as NSString).lastPathComponent
                // Skip .app bundles — don't walk inside them
                if fileName.hasSuffix(".app") {
                    enumerator.skipDescendants()
                    continue
                }
                if fileName == ".DS_Store" {
                    let (f, _) = (try? removeFile(fullPath, dryRun: dryRun, progress: nil)) ?? (0, nil)
                    freed += f
                }
            }
        }
        
        // __MACOSX directories
        let macosxDirs = [home]
        for dir in macosxDirs {
            guard fm.fileExists(atPath: dir) else { continue }
            guard let enumerator = fm.enumerator(atPath: dir) else { continue }
            while let item = enumerator.nextObject() as? String {
                try Task.checkCancellation()
                let fileName = (item as NSString).lastPathComponent
                if fileName == "__MACOSX" {
                    let fullPath = "\(dir)/\(item)"
                    let (f, _) = (try? removeDirectory(fullPath, dryRun: dryRun, progress: nil)) ?? (0, nil)
                    freed += f
                }
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.log("Scattered junk total: \(Self.formatBytes(freed))"))
        progress?(.result(label: "Scattered junk", freedMB: mb))
        return [CleanupEngineResult(label: "Scattered junk", freedMB: mb)]
    }

    // MARK: 19. Orphaned Remnants

    func cleanOrphanedRemnants(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning orphaned remnants..."))
        var freed: Int64 = 0

        // Old iOS DeviceSupport
        let (f, item) = try cleanContents(of: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", dryRun: dryRun, progress: progress)
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
            "\(home)/Library/Group Containers"
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

                if !isEntryInstalled(entry, installedApps: installedApps) {
                    let entryPath = "\(scanDir)/\(entry)"
                    let entrySize = try getDirectorySize(entryPath)
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
                if !isEntryInstalled(entry, installedApps: installedApps) {
                    let entryPath = "\(httpStorages)/\(entry)"
                    let entrySize = try getDirectorySize(entryPath)
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

        // Scan ~/Library/WebKit for orphaned entries
        let webkitDir = "\(home)/Library/WebKit"
        if fm.fileExists(atPath: webkitDir) {
            let entries = (try? fm.contentsOfDirectory(atPath: webkitDir)) ?? []
            for entry in entries {
                if entry.hasPrefix("com.apple.") { continue }
                if !isEntryInstalled(entry, installedApps: installedApps) {
                    let entryPath = "\(webkitDir)/\(entry)"
                    let entrySize = try getDirectorySize(entryPath)
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

    // MARK: 21. Large Files

    func cleanLargeFiles(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        progress?(.log("Scanning large files..."))
        var totalFound: Int64 = 0
        var items: [(String, Int64)] = []

        // Old DMG installers in Downloads
        let downloads = "\(home)/Downloads"
        if fm.fileExists(atPath: downloads) {
            progress?(.log("  Scanning ~/Downloads for DMG/pkg/iso/zip > 100 MB, older than 30 days..."))
            let contents = try? fm.contentsOfDirectory(atPath: downloads)
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            var scannedCount = 0
            for file in (contents ?? []) {
                let ext = (file as NSString).pathExtension.lowercased()
                if ["dmg", "pkg", "iso", "zip"].contains(ext) {
                    let filePath = "\(downloads)/\(file)"
                    if let attrs = try? fm.attributesOfItem(atPath: filePath),
                       let modDate = attrs[.modificationDate] as? Date,
                       modDate < cutoffDate,
                       let size = attrs[.size] as? Int64, size > 100 * 1024 * 1024 {
                        items.append(("Downloads/\(file)", size))
                        totalFound += size
                        if dryRun {
                            emitFileItem(CleanupFileItem(path: filePath, sizeBytes: size, modificationDate: modDate, isDirectory: false), category: "Large files", parentName: nil, progress: progress)
                        }
                    }
                }
                scannedCount += 1
            }
            progress?(.log("  Checked \(scannedCount) files in Downloads"))
        }

        // node_modules directories > 100MB
        progress?(.log("  Scanning home directory for node_modules > 100 MB..."))
        let homeContents = try? fm.contentsOfDirectory(atPath: home)
        for dir in (homeContents ?? []) {
            let nodeModulesPath = "\(home)/\(dir)/node_modules"
            if fm.fileExists(atPath: nodeModulesPath) {
                let size = try getDirectorySize(nodeModulesPath)
                if size > 100 * 1024 * 1024 {
                    items.append(("~/\(dir)/node_modules", size))
                    totalFound += size
                    if dryRun {
                        emitFileItem(CleanupFileItem(path: nodeModulesPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Large files", parentName: nil, progress: progress)
                    }
                }
            }
        }

        // iPhone/iPad backups (MobileSync)
        let mobileSync = "\(home)/Library/Application Support/MobileSync/Backup"
        if fm.fileExists(atPath: mobileSync) {
            let size = try getDirectorySize(mobileSync)
            if size > 0 {
                items.append(("MobileSync/Backup", size))
                totalFound += size
                if dryRun {
                    emitFileItem(CleanupFileItem(path: mobileSync, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Large files", parentName: nil, progress: progress)
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
                let ext = (item as NSString).pathExtension.lowercased()
                if ext == "ipsw" {
                    let fullPath = "\(dir)/\(item)"
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

        // Mail downloads
        let mailPath = "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        if fm.fileExists(atPath: mailPath) {
            let size = try getDirectorySize(mailPath)
            if size > 0 {
                items.append(("Mail Downloads", size))
                totalFound += size
                if dryRun {
                    emitFileItem(CleanupFileItem(path: mailPath, sizeBytes: size, modificationDate: nil, isDirectory: true), category: "Large files", parentName: nil, progress: progress)
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

            let entryPath = "\(cachesDir)/\(entry)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entryPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let size = try getDirectorySize(entryPath)
            if size < 5 * 1024 * 1024 { // < 5 MB, skip
                continue
            }

            // Check if it's a known-safe reverse-DNS pattern for auto-clean (com.*, org.*, io.*, etc.)
            let isSafePattern = entry.contains(".") && (entry.hasPrefix("com.") || entry.hasPrefix("org.") || entry.hasPrefix("io.") || entry.hasPrefix("net.") || entry.hasPrefix("co."))

            if dryRun {
                // In scan mode: show ALL entries >= 5 MB
                let isAutoClean = isSafePattern && size >= 50 * 1024 * 1024
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
                // In cleanup mode: only auto-clean safe patterns >= 50 MB
                if isSafePattern && size >= 50 * 1024 * 1024 {
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
}


