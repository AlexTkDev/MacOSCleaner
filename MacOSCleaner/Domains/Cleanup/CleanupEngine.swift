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
    private let commandRunner: CommandRunner
    private let safetyManager: SafetyManager
    private let timeouts: CleanupTimeouts
    private let fm = FileManager.default

    public init(
        commandRunner: CommandRunner = CommandRunner(),
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
                categoryResults = try await withTimeout(timeouts.fast) {
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
                categoryResults = []
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
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw CleanupEngineError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
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
        }
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

// MARK: - FileManager Helpers

extension CleanupEngine {

    /// Safely cleans directory contents (the directory itself is preserved).
    /// Returns freed bytes.
    func cleanContents(of path: String, dryRun: Bool) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else { return 0 }
        let before = try getDirectorySize(path)

        if dryRun { return before }

        let contents = try fm.contentsOfDirectory(atPath: path)
        for item in contents {
            let itemURL = url.appendingPathComponent(item)
            try? fm.removeItem(at: itemURL)
        }

        let after = try getDirectorySize(path)
        return max(0, before - after)
    }

    /// Removes an entire directory.
    func removeDirectory(_ path: String, dryRun: Bool) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else { return 0 }
        let before = try getDirectorySize(path)

        if dryRun { return before }

        try? fm.removeItem(atPath: path)
        return before
    }

    /// Removes a file.
    func removeFile(_ path: String, dryRun: Bool) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        try safetyManager.validate(url: url)

        guard fm.fileExists(atPath: path) else { return 0 }
        let attrs = try fm.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? Int64) ?? 0

        if dryRun { return size }

        try? fm.removeItem(atPath: path)
        return size
    }

    /// Returns directory size in bytes.
    func getDirectorySize(_ path: String) throws -> Int64 {
        let url = URL(fileURLWithPath: path)
        return fm.getDirectorySize(url: url)
    }

    /// Returns true if the command is available in the system.
    func commandExists(_ command: String) -> Bool {
        var isDir: ObjCBool = false
        let path = "/usr/bin/env \(command)"
        return fm.fileExists(atPath: path, isDirectory: &isDir) ||
               fm.fileExists(atPath: "/usr/local/bin/\(command)") ||
               fm.fileExists(atPath: "/opt/homebrew/bin/\(command)")
    }

    /// Removes old files (older than N days) from a directory.
    func cleanOldFiles(in path: String, olderThanDays days: Int, dryRun: Bool) throws -> Int64 {
        guard fm.fileExists(atPath: path) else { return 0 }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var freed: Int64 = 0

        let contents = try fm.contentsOfDirectory(atPath: path)
        for item in contents {
            let itemURL = URL(fileURLWithPath: path).appendingPathComponent(item)
            let attrs = try? fm.attributesOfItem(atPath: itemURL.path)
            if let modDate = attrs?[.modificationDate] as? Date, modDate < cutoffDate {
                let size = (attrs?[.size] as? Int64) ?? 0
                if !dryRun {
                    try? fm.removeItem(at: itemURL)
                }
                freed += size
            }
        }
        return freed
    }
}

// MARK: - Category Implementations: FileManager-Based

extension CleanupEngine {

    // MARK: 1. App Caches

    func cleanAppCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
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
            let freed = try cleanContents(of: dir, dryRun: dryRun)
            totalFreed += freed
        }

        // Google Updater Plists
        let plistPaths = [
            "\(home)/Library/Preferences/com.google.Keystone.Agent.plist",
            "\(home)/Library/LaunchAgents/com.google.keystone.xpcservice.plist",
            "\(home)/Library/LaunchAgents/com.google.keystone.agent.plist",
            "\(home)/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist"
        ]
        for plist in plistPaths {
            try Task.checkCancellation()
            totalFreed += try removeFile(plist, dryRun: dryRun)
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.result(label: "Selected app caches", freedMB: mb))
        return [CleanupEngineResult(label: "Selected app caches", freedMB: mb)]
    }

    // MARK: 2. Package Managers (FileManager + Process)

    func cleanPackageManagers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        var results: [CleanupEngineResult] = []
        let home = fm.homeDirectoryForCurrentUser.path

        // Homebrew
        if await commandRunner.commandExists("brew") {
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "brew --cache 2>/dev/null"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheDir = cachePath ?? "\(home)/Library/Caches/Homebrew"

            if dryRun {
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.result(label: "Homebrew cache", freedMB: size))
                results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: size))
            } else {
                let before = try getDirectorySize(cacheDir)
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "brew cleanup --prune=all -q"])
                let after = try getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.result(label: "Homebrew cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "Homebrew cache", freedMB: freed))
            }
        }

        // npm
        if await commandRunner.commandExists("npm") {
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "npm config get cache 2>/dev/null"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheDir = cachePath ?? "\(home)/.npm"

            if dryRun {
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.result(label: "npm cache", freedMB: size))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: size))
            } else {
                let before = try getDirectorySize(cacheDir)
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "npm cache clean --force 2>/dev/null"])
                let after = try getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.result(label: "npm cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "npm cache", freedMB: freed))
            }
        }

        // yarn
        if await commandRunner.commandExists("yarn") {
            let cachePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "yarn cache dir 2>/dev/null"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheDir = cachePath ?? "\(home)/Library/Caches/Yarn"

            if dryRun {
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.result(label: "yarn cache", freedMB: size))
                results.append(CleanupEngineResult(label: "yarn cache", freedMB: size))
            } else {
                let before = try getDirectorySize(cacheDir)
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "yarn cache clean 2>/dev/null"])
                let after = try getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.result(label: "yarn cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "yarn cache", freedMB: freed))
            }
        }

        // pnpm
        if await commandRunner.commandExists("pnpm") {
            let storePath = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "pnpm store path 2>/dev/null"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let storeDir = storePath ?? "\(home)/Library/pnpm/store"

            if dryRun {
                let size = Int(try getDirectorySize(storeDir) / (1024 * 1024))
                progress?(.result(label: "pnpm store", freedMB: size))
                results.append(CleanupEngineResult(label: "pnpm store", freedMB: size))
            } else {
                let before = try getDirectorySize(storeDir)
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "pnpm store prune 2>/dev/null"])
                let after = try getDirectorySize(storeDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.result(label: "pnpm store", freedMB: freed))
                results.append(CleanupEngineResult(label: "pnpm store", freedMB: freed))
            }
        }

        // CocoaPods
        if await commandRunner.commandExists("pod") {
            let cacheDir = "\(home)/Library/Caches/CocoaPods"
            if dryRun {
                let size = Int(try getDirectorySize(cacheDir) / (1024 * 1024))
                progress?(.result(label: "CocoaPods cache", freedMB: size))
                results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: size))
            } else {
                let before = try getDirectorySize(cacheDir)
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "pod cache clean --all 2>/dev/null"])
                let after = try getDirectorySize(cacheDir)
                let freed = Int(max(0, before - after) / (1024 * 1024))
                progress?(.result(label: "CocoaPods cache", freedMB: freed))
                results.append(CleanupEngineResult(label: "CocoaPods cache", freedMB: freed))
            }
        }

        return results
    }

    // MARK: 3. Gradle + Maven

    func cleanGradleMaven(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanContents(of: "\(home)/.gradle/caches", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.gradle/wrapper/dists", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.gradle/daemon", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.gradle/buildOutputCleanup", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.kotlin", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Gradle caches + wrapper + daemon", freedMB: mb))
        return [CleanupEngineResult(label: "Gradle + Maven", freedMB: mb)]
    }

    // MARK: 4. Flutter / Dart

    func cleanFlutterDart(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanContents(of: "\(home)/.pub-cache/hosted", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.pub-cache/git", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.dartServer", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Dart/Flutter package caches", freedMB: mb))
        return [CleanupEngineResult(label: "Flutter / Dart", freedMB: mb)]
    }

    // MARK: 5. Xcode

    func cleanXcode(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/DerivedData", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/watchOS DeviceSupport", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/visionOS DeviceSupport", dryRun: dryRun)
        freed += try cleanOldFiles(in: "\(home)/Library/Developer/Xcode/Archives", olderThanDays: 90, dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/DocumentationCache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/UserData/IB Support", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/UserData/Previews/Simulator Devices", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/Products", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/clangd", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Xcode cleanup", freedMB: mb))
        return [CleanupEngineResult(label: "Xcode", freedMB: mb)]
    }

    // MARK: 6. iOS Simulators

    func cleanIOSSimulators(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanContents(of: "\(home)/Library/Developer/CoreSimulator/Caches", dryRun: dryRun)

        if await commandRunner.commandExists("xcrun") {
            if dryRun {
                let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl list devices 2>/dev/null | grep -c 'unavailable' || echo 0"])
                let count = Int(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
                progress?(.log("Unavailable simulator devices: \(count)"))
            } else {
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "xcrun simctl delete unavailable 2>/dev/null"])
            }
        }

        // Clean simulator app caches
        let devicesPath = "\(home)/Library/Developer/CoreSimulator/Devices"
        if fm.fileExists(atPath: devicesPath) {
            let devices = try? fm.contentsOfDirectory(atPath: devicesPath)
            for device in (devices ?? []) {
                let cachesPath = "\(devicesPath)/\(device)/data/Library/Caches"
                let tmpPath = "\(devicesPath)/\(device)/data/tmp"
                freed += try cleanContents(of: cachesPath, dryRun: dryRun)
                freed += try cleanContents(of: tmpPath, dryRun: dryRun)
            }
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Simulator caches", freedMB: mb))
        return [CleanupEngineResult(label: "iOS Simulators", freedMB: mb)]
    }

    // MARK: 7. Android Caches

    func cleanAndroidCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanContents(of: "\(home)/.android/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.android/build-cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Android/sdk/.temp", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Android build caches", freedMB: mb))
        return [CleanupEngineResult(label: "Android caches", freedMB: mb)]
    }

    // MARK: 8. Android SDK

    func cleanAndroidSDK(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        let sdkPath = "\(home)/Library/Android/sdk"

        // Find sdkmanager
        var sdkmanager: String?
        let candidates = [
            "\(sdkPath)/cmdline-tools/latest/bin/sdkmanager",
            "\(sdkPath)/tools/bin/sdkmanager"
        ]
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                sdkmanager = path
                break
            }
        }

        var freed: Int64 = 0

        // Clean build-tools (keep latest stable)
        if fm.fileExists(atPath: "\(sdkPath)/build-tools"), let sdkmanager {
            let versions = try? fm.contentsOfDirectory(atPath: "\(sdkPath)/build-tools")
            let stableVersions = (versions ?? []).filter { !$0.lowercased().contains("rc") && !$0.lowercased().contains("alpha") && !$0.lowercased().contains("beta") && !$0.lowercased().contains("preview") }
            let keepVersion = stableVersions.last

            for version in (versions ?? []) {
                guard version != keepVersion else { continue }
                let dir = "\(sdkPath)/build-tools/\(version)"
                freed += try removeDirectory(dir, dryRun: dryRun)
            }
        }

        // Clean platforms (keep latest)
        if fm.fileExists(atPath: "\(sdkPath)/platforms"), let sdkmanager {
            let versions = try? fm.contentsOfDirectory(atPath: "\(sdkPath)/platforms")
            let keepVersion = versions?.last

            for version in (versions ?? []) {
                guard version != keepVersion else { continue }
                let dir = "\(sdkPath)/platforms/\(version)"
                freed += try removeDirectory(dir, dryRun: dryRun)
            }
        }

        let mb = Int(freed / (1024 * 1024))
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
        ]

        var totalFreed: Int64 = 0
        for dir in ideDirs {
            try Task.checkCancellation()
            totalFreed += try cleanContents(of: dir, dryRun: dryRun)
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.result(label: "IDE / Electron caches", freedMB: mb))
        return [CleanupEngineResult(label: "IDE / Electron caches", freedMB: mb)]
    }

    // MARK: 10. Browser Caches

    func cleanBrowserCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        let browserDirs = [
            "\(home)/Library/Caches/com.apple.Safari",
            "\(home)/Library/Safari/Favicon Cache",
            "\(home)/Library/Caches/com.brave.Browser",
            "\(home)/Library/Caches/com.operasoftware.Opera",
            "\(home)/Library/Caches/com.microsoft.Edge",
            "\(home)/Library/Caches/org.mozilla.firefox",
            "\(home)/Library/Caches/Firefox",
            "\(home)/Library/Caches/com.google.Chrome",
            "\(home)/Library/Caches/com.google.Chrome.beta"
        ]

        var totalFreed: Int64 = 0
        for dir in browserDirs {
            try Task.checkCancellation()
            totalFreed += try cleanContents(of: dir, dryRun: dryRun)
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.result(label: "Browser caches", freedMB: mb))
        return [CleanupEngineResult(label: "Browser caches", freedMB: mb)]
    }

    // MARK: 11. Messaging / Media

    func cleanMessagingMedia(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        let dirs = [
            "\(home)/Library/Caches/ru.keepcoder.Telegram",
            "\(home)/Library/Caches/com.tinyspeck.slackmacgap",
            "\(home)/Library/Caches/com.hnc.Discord",
            "\(home)/Library/Caches/us.zoom.xos",
            "\(home)/Library/Messages/Attachments"
        ]

        var totalFreed: Int64 = 0
        for dir in dirs {
            try Task.checkCancellation()
            totalFreed += try cleanContents(of: dir, dryRun: dryRun)
        }

        let mb = Int(totalFreed / (1024 * 1024))
        progress?(.result(label: "Messaging / media caches", freedMB: mb))
        return [CleanupEngineResult(label: "Messaging / media", freedMB: mb)]
    }

    // MARK: 12. Docker

    func cleanDocker(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        guard await commandRunner.commandExists("docker") else {
            return [CleanupEngineResult(label: "Docker", freedMB: 0)]
        }

        if dryRun {
            let result = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "docker system df 2>/dev/null"])
            progress?(.log("Docker disk usage:\n\(result?.stdout ?? "N/A")"))
            return [CleanupEngineResult(label: "Docker", freedMB: 0)]
        } else {
            _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "docker system prune -af --volumes 2>/dev/null"])
            progress?(.result(label: "Docker cleanup", freedMB: 0))
            return [CleanupEngineResult(label: "Docker", freedMB: 0)]
        }
    }

    // MARK: 13. Language Caches

    func cleanLanguageCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        // Rust / Cargo
        freed += try cleanContents(of: "\(home)/.cargo/registry/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cargo/registry/src", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cargo/.package-cache", dryRun: dryRun)

        // Bun
        freed += try cleanContents(of: "\(home)/.bun/install/cache", dryRun: dryRun)

        // Deno
        freed += try cleanContents(of: "\(home)/.deno/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/deno", dryRun: dryRun)

        // Volta
        freed += try cleanContents(of: "\(home)/.volta/cache", dryRun: dryRun)

        // NVM
        freed += try cleanContents(of: "\(home)/.nvm/.cache", dryRun: dryRun)

        // node-gyp
        freed += try cleanContents(of: "\(home)/.cache/node-gyp", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.node-gyp", dryRun: dryRun)

        // Cypress
        freed += try cleanContents(of: "\(home)/.cache/Cypress", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/Cypress", dryRun: dryRun)

        // Playwright
        freed += try cleanContents(of: "\(home)/.cache/ms-playwright", dryRun: dryRun)

        // Puppeteer
        freed += try cleanContents(of: "\(home)/.cache/puppeteer", dryRun: dryRun)

        // Ruby
        let gemRubyPath = "\(home)/.gem/ruby"
        if fm.fileExists(atPath: gemRubyPath) {
            let versions = try? fm.contentsOfDirectory(atPath: gemRubyPath)
            for ver in (versions ?? []) {
                freed += try cleanContents(of: "\(gemRubyPath)/\(ver)/cache", dryRun: dryRun)
            }
        }
        freed += try cleanContents(of: "\(home)/.bundle/cache", dryRun: dryRun)

        // PHP / Composer
        freed += try cleanContents(of: "\(home)/.composer/cache", dryRun: dryRun)

        // Python
        freed += try cleanContents(of: "\(home)/Library/Caches/pypoetry", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/uv", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cache/pip", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cache/pypoetry", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cache/uv", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cache/hatch", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.rye/cache", dryRun: dryRun)

        // JVM
        freed += try cleanContents(of: "\(home)/.sbt", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.ivy2/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.coursier/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.ammonite/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cache/metals", dryRun: dryRun)

        // Julia
        freed += try cleanContents(of: "\(home)/.julia/compiled", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.julia/logs", dryRun: dryRun)

        // Elixir / Hex
        freed += try cleanContents(of: "\(home)/.hex/packages", dryRun: dryRun)

        // Haskell
        freed += try cleanContents(of: "\(home)/.cabal/packages", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.cabal/logs", dryRun: dryRun)

        // Swift PM
        freed += try cleanContents(of: "\(home)/.cache/org.swift.swiftpm", dryRun: dryRun)

        // Go (build cache via command)
        if await commandRunner.commandExists("go") {
            if !dryRun {
                _ = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "go clean -cache 2>/dev/null"])
            }
        }

        // Go module cache (if cleanModCache enabled — in full mode we always clean)
        if await commandRunner.commandExists("go") {
            let goModCache = try? await commandRunner.run(command: "/bin/bash", arguments: ["-c", "go env GOMODCACHE 2>/dev/null"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let modPath = goModCache ?? "\(home)/go/pkg/mod"
            freed += try cleanContents(of: modPath, dryRun: dryRun)
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Language caches", freedMB: mb))
        return [CleanupEngineResult(label: "Language caches", freedMB: mb)]
    }

    // MARK: 14. User Logs

    func cleanUserLogs(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanOldFiles(in: "\(home)/Library/Logs", olderThanDays: 7, dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Logs/DiagnosticReports", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Logs/CrashReporter", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Application Support/CrashReporter", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "User logs", freedMB: mb))
        return [CleanupEngineResult(label: "User logs", freedMB: mb)]
    }

    // MARK: 15. System Caches

    func cleanSystemCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanContents(of: "\(home)/Library/Caches/com.apple.QuickLook.thumbnailcache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/com.apple.fontd", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/com.apple.iconservices", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/com.apple.metadata.SpotlightIndex", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/com.apple.Siri", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/com.apple.Assistant", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/Library/Caches/com.apple.parsecd", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "System caches", freedMB: mb))
        return [CleanupEngineResult(label: "System caches", freedMB: mb)]
    }

    // MARK: 16. App Containers

    func cleanAppContainers(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        let containersPath = "\(home)/Library/Containers"
        var freed: Int64 = 0

        guard fm.fileExists(atPath: containersPath) else {
            return [CleanupEngineResult(label: "App containers", freedMB: 0)]
        }

        let containers = try? fm.contentsOfDirectory(atPath: containersPath)
        for container in (containers ?? []) {
            try Task.checkCancellation()
            let dataCaches = "\(containersPath)/\(container)/Data/Library/Caches"
            freed += try cleanContents(of: dataCaches, dryRun: dryRun)
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "App container caches", freedMB: mb))
        return [CleanupEngineResult(label: "App containers", freedMB: mb)]
    }

    // MARK: 17. Dotfile Caches

    func cleanDotfileCaches(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        freed += try cleanContents(of: "\(home)/.cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.config/claude-cli/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.config/gemini/cache", dryRun: dryRun)
        freed += try cleanContents(of: "\(home)/.local/share/Trash", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Dotfile caches", freedMB: mb))
        return [CleanupEngineResult(label: "Dotfile caches", freedMB: mb)]
    }

    // MARK: 18. Scattered Junk

    func cleanScatteredJunk(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        // .DS_Store files in home
        let dsStorePaths = [
            "\(home)/.DS_Store"
        ]
        for path in dsStorePaths {
            freed += try removeFile(path, dryRun: dryRun)
        }

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Scattered junk", freedMB: mb))
        return [CleanupEngineResult(label: "Scattered junk", freedMB: mb)]
    }

    // MARK: 19. Orphaned Remnants

    func cleanOrphanedRemnants(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        let home = fm.homeDirectoryForCurrentUser.path
        var freed: Int64 = 0

        // Old iOS DeviceSupport
        freed += try cleanContents(of: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", dryRun: dryRun)

        let mb = Int(freed / (1024 * 1024))
        progress?(.result(label: "Orphaned remnants", freedMB: mb))
        return [CleanupEngineResult(label: "Orphaned remnants", freedMB: mb)]
    }

    // MARK: 20. Orphaned Files

    func cleanOrphanedFiles(dryRun: Bool, progress: (@Sendable (CleanupEngineEvent) -> Void)?) async throws -> [CleanupEngineResult] {
        // Orphaned application files are typically safe to clean
        // For now, return empty - this requires more sophisticated detection
        return [CleanupEngineResult(label: "Orphaned files", freedMB: 0)]
    }
}

// MARK: - CommandRunner Extension

private extension CommandRunner {
    func commandExists(_ command: String) async -> Bool {
        let result = try? await run(command: "/bin/bash", arguments: ["-c", "command -v \(command) 2>/dev/null"])
        return result?.exitCode == 0
    }
}
