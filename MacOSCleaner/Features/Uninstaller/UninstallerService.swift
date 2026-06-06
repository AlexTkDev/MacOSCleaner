import Foundation
import SwiftUI
import AppKit
import OSLog

private extension Logger {
    static let uninstaller = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "UninstallerService")
}

@Observable
public final class ScanProgress: @unchecked Sendable {
    public var currentStep: Int = 0
    public var totalSteps: Int = 1
    public var message: String = ""
    public var percentage: Double = 0.0
    
    public init() {}
}

public actor UninstallerService {
    public let progress = ScanProgress()
    private let fileManager: FileManager
    private let safetyManager: SafetyManager
    private let trashManager: TrashManager
    private let commandRunner: CommandRunner

    public init(
        fileManager: FileManager = .default,
        safetyManager: SafetyManager = SafetyManager(),
        trashManager: TrashManager = TrashManager(),
        commandRunner: CommandRunner = CommandRunner()
    ) {
        self.fileManager = fileManager
        self.safetyManager = safetyManager
        self.trashManager = trashManager
        self.commandRunner = commandRunner
    }

    public struct RelatedFile: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let url: URL
        public var isSelected: Bool = true
        public let size: Int64
        
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: RelatedFile, rhs: RelatedFile) -> Bool { lhs.id == rhs.id }
    }

    public struct AppInfo: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let url: URL
        public let bundleID: String?
        public let name: String
        public var relatedFiles: [RelatedFile] = []
        
        public var size: Int64 = 0
        public var version: String = ""
        public var lastUsed: Date? = nil
        public var icon: NSImage? = nil
        
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
        
        public var totalSize: Int64 {
            let relatedSize = relatedFiles.filter(\.isSelected).reduce(0) { $0 + $1.size }
            return size + relatedSize
        }
    }

    public func scanAllApplications() async throws -> [AppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        ]
        
        // Count apps first for progress
        var allAppURLsBuilder: [URL] = []
        for dir in appDirs {
            if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                allAppURLsBuilder.append(contentsOf: contents.filter { $0.pathExtension == "app" })
            }
        }
        
        // Also find apps in Application Support (like Google Updater)
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            let appSupportDir = home + "/Library/Application Support"
            do {
                let result = try await commandRunner.run(command: "/usr/bin/find", arguments: [appSupportDir, "-maxdepth", "4", "-name", "*.app", "-type", "d", "-prune"])
                let paths = result.stdout.components(separatedBy: .newlines)
                for path in paths where !path.isEmpty {
                    allAppURLsBuilder.append(URL(fileURLWithPath: path))
                }
            } catch {
                Logger.uninstaller.warning("Failed to search Application Support for apps: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        let allAppURLs = Array(Set(allAppURLsBuilder)) // Remove duplicates
        
        await MainActor.run {
            progress.currentStep = 0
            progress.totalSteps = allAppURLs.count
            progress.message = "Scanning applications..."
            progress.percentage = 0.0
        }
        
        return try await withThrowingTaskGroup(of: AppInfo?.self) { group in
            for url in allAppURLs {
                group.addTask {
                    let app = try? await self.scan(appURL: url)
                    await MainActor.run {
                        self.progress.currentStep += 1
                        self.progress.percentage = Double(self.progress.currentStep) / Double(self.progress.totalSteps)
                    }
                    return app
                }
            }
            
            var apps: [AppInfo] = []
            for try await app in group {
                if let app = app {
                    apps.append(app)
                }
            }
            
            await MainActor.run {
                progress.message = "Scan complete"
                progress.percentage = 1.0
            }
            
            return apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    public func scan(appURL: URL) async throws -> AppInfo {
        try safetyManager.validate(url: appURL)
        
        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier
        let appName = appURL.deletingPathExtension().lastPathComponent
        let infoDictionary = bundle?.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? 
                     infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        
        let size = await getDirectorySize(url: appURL)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        let mdItem = MDItemCreate(nil, appURL.path as CFString)
        let lastUsed = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date
        
        var relatedURLs = Set<URL>()
        let searchPatterns = createSearchPatterns(bundleID: bundleID, appName: appName)
        
        // Pass 1: mdfind (Spotlight)
        let mdfindResults = await runMdfind(bundleID: bundleID, appName: appName)
        relatedURLs.formUnion(mdfindResults)
        
        // Pass 2: pkgutil (Receipts)
        relatedURLs.formUnion(await getPkgFiles(bundleID: bundleID))
        
        // Pass 3: Manual scanning of expanded paths (Depth search)
        var libraryPaths = [
            "~/Library/Application Support",
            "~/Library/Caches",
            "~/Library/Containers",
            "~/Library/Group Containers",
            "~/Library/Cookies",
            "~/Library/Logs",
            "~/Library/Preferences",
            "~/Library/Saved Application State",
            "~/Library/LaunchAgents",
            "~/Library/Application Scripts",
            "~/Library/HTTPStorages",
            "~/Library/WebKit",
            "/Library/Application Support",
            "/Library/Caches",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Preferences",
            "/Library/PrivilegedHelperTools",
            "~/Library",
            "~/Library/Developer",
            "~/Library/Android",
            "~/",
            "/tmp",
            "/private/tmp",
            "/usr/local/bin",
            "/usr/local/share",
            "/Library/Frameworks",
            "/Library/Internet Plug-Ins"
        ]
        
        libraryPaths.append(contentsOf: getSystemSearchPaths())
        
        let teamID = await getTeamIdentifier(url: appURL)
        let deepScanFolders = ["Application Support", "Caches", "Logs", "Developer", "Containers", "Group Containers", "HTTPStorages", "WebKit"]
        
        for path in libraryPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            let folderURL = URL(fileURLWithPath: expandedPath)
            
            // Shallow scan first level
            let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [])) ?? []
            
            for fileURL in contents {
                if fileURL.path == appURL.path { continue }
                
                let fileName = fileURL.lastPathComponent
                
                // If scanning HOME, only look at hidden files or if it matches a pattern exactly
                if path == "~/" || path == "~" {
                    if !fileName.hasPrefix(".") && !matches(fileName: fileName, patterns: searchPatterns) {
                        continue
                    }
                }

                // Check by pattern
                if matches(fileName: fileName, patterns: searchPatterns) {
                    relatedURLs.insert(fileURL)
                } 
                // Check by Team ID for binaries/kexts in specific folders
                else if (path.contains("Launch") || path.contains("Privileged") || path.contains("Extensions")) {
                    let fileTeamID = await getTeamIdentifier(url: fileURL)
                    if fileTeamID == teamID && teamID != nil {
                        relatedURLs.insert(fileURL)
                    }
                }
                // 3-level recursive check for vendor folders
                else if deepScanFolders.contains(folderURL.lastPathComponent) {
                    let subContents = (try? fileManager.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil, options: [])) ?? []
                    for subURL in subContents {
                        if matches(fileName: subURL.lastPathComponent, patterns: searchPatterns) {
                            relatedURLs.insert(subURL)
                        } else {
                            // Try one more level for possible vendor folders (e.g. Google/AndroidStudio)
                            let vendorSubContents = (try? fileManager.contentsOfDirectory(at: subURL, includingPropertiesForKeys: nil, options: [])) ?? []
                            for vendorSubURL in vendorSubContents {
                                if matches(fileName: vendorSubURL.lastPathComponent, patterns: searchPatterns) {
                                    relatedURLs.insert(vendorSubURL)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Verification & Size Calculation
        var related: [RelatedFile] = []
        for url in relatedURLs {
            // Safety check
            if (try? safetyManager.validate(url: url)) == nil { continue }
            if url.path == appURL.path || appURL.path.hasPrefix(url.path + "/") { continue }
            
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                let fileSize = await getDirectorySize(url: url)
                related.append(RelatedFile(url: url, size: fileSize))
            }
        }
        
        return AppInfo(
            url: appURL,
            bundleID: bundleID,
            name: appName,
            relatedFiles: related.sorted { $0.url.path < $1.url.path },
            size: size,
            version: version,
            lastUsed: lastUsed,
            icon: icon
        )
    }

    private func getDirectorySize(url: URL) async -> Int64 {
        var size: Int64 = 0
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [])
        while let fileURL = enumerator?.nextObject() as? URL {
            // Skip OrbStack sparse files to avoid massive false positive sizes
            if fileURL.path.contains(".dev.orbstack") {
                continue
            }
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            size += Int64(resourceValues?.fileSize ?? 0)
        }
        return size
    }

    func getSystemSearchPaths() -> [String] {
        var paths = [String]()
        
        // DARWIN_USER_CACHE_DIR and TEMP_DIR are under /var/folders/
        // NSTemporaryDirectory() usually points to the 'T' directory
        let tmpDir = NSTemporaryDirectory()
        if !tmpDir.isEmpty {
            paths.append(tmpDir)
            // Replace /T/ with /C/ for cache directory
            let cacheDir = tmpDir.replacingOccurrences(of: "/T/", with: "/C/")
            if fileManager.fileExists(atPath: cacheDir) {
                paths.append(cacheDir)
            }
        }
        
        return paths
    }

    func createSearchPatterns(bundleID: String?, appName: String) -> [String] {
        var patterns = Set<String>()
        if let bundleID = bundleID {
            patterns.insert(bundleID)
            let parts = bundleID.components(separatedBy: ".")
            if parts.count >= 2 {
                // Add all suffixes: com.apple.dt.Xcode -> apple.dt.Xcode, dt.Xcode, Xcode
                for i in 1..<parts.count {
                    patterns.insert(parts.dropFirst(i).joined(separator: "."))
                }
            }
        }
        
        let cleanedAppName = appName.replacingOccurrences(of: " ", with: "")
        patterns.insert(appName)
        patterns.insert(cleanedAppName)
        patterns.insert(appName.replacingOccurrences(of: " ", with: "-"))
        
        // Split app name into words (e.g., "Android Studio" -> "Android", "Studio")
        let words = appName.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-.")))
        for word in words where word.count >= 4 {
            patterns.insert(word)
        }
        
        // Add extra patterns for known apps
        patterns.formUnion(getExtraPatterns(appName: appName, bundleID: bundleID))
        
        return Array(patterns).filter { $0.count >= 3 }
    }

    func getExtraPatterns(appName: String, bundleID: String?) -> [String] {
        var extra: [String] = []
        let lowerName = appName.lowercased()
        let lowerID = bundleID?.lowercased() ?? ""
        
        if lowerName.contains("xcode") || lowerID.contains("com.apple.dt.xcode") {
            extra.append(contentsOf: ["Instruments", "Simulator", "iphonesimulator", "llvm", "clang"])
        }
        if lowerName.contains("android") || lowerID.contains("android") {
            extra.append(contentsOf: ["android", "emulator", "gradle", "jetbrains", "studio"])
        }
        if lowerName.contains("flutter") || lowerID.contains("flutter") {
            extra.append(contentsOf: ["mobileinstallation", "flutter", "dart"])
        }
        if lowerName.contains("cleaner") || lowerID.contains("cleaner") {
            extra.append("macoscleaner")
        }
        
        return extra
    }

    private func matches(fileName: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if fileName.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }
        return false
    }

    private func runMdfind(bundleID: String?, appName: String) async -> Set<URL> {
        var urls = Set<URL>()
        let query = bundleID ?? appName
        
        do {
            let result = try await commandRunner.run(command: "/usr/bin/mdfind", arguments: [query])
            let paths = result.stdout.components(separatedBy: .newlines)
            for path in paths where !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                let pathStr = url.path
                if pathStr.contains("/Library/") || pathStr.contains("/tmp/") || pathStr.hasPrefix("/private/var/folders/") {
                    urls.insert(url)
                }
            }
        } catch {
            print("mdfind failed: \(error)")
        }
        
        return urls
    }

    private func getPkgFiles(bundleID: String?) async -> Set<URL> {
        guard let bundleID = bundleID else { return [] }
        let result = try? await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--files", bundleID])
        guard let output = result?.stdout else { return [] }
        
        var urls = Set<URL>()
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            let path = "/\(line)"
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                urls.insert(url)
            }
        }
        return urls
    }

    private func getTeamIdentifier(url: URL) async -> String? {
        let result = try? await commandRunner.run(command: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", url.path])
        guard let output = result?.stderr else { return nil }
        
        if let range = output.range(of: "TeamIdentifier=") {
            let start = range.upperBound
            let end = output[start...].firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? output.endIndex
            return String(output[start..<end])
        }
        return nil
    }

    public func uninstall(app: AppInfo, bypassTrash: Bool = false, emptyTrashImmediately: Bool = false) async throws {
        Logger.uninstaller.info("Uninstalling '\(app.name, privacy: .public)' bypassTrash=\(bypassTrash)")

        // 1. Unload launch agents/daemons
        for file in app.relatedFiles where file.isSelected {
            let path = file.url.path
            if (path.contains("LaunchAgents") || path.contains("LaunchDaemons")), path.hasSuffix(".plist") {
                do {
                    _ = try await commandRunner.run(command: "/bin/launchctl", arguments: ["unload", path])
                    Logger.uninstaller.debug("Unloaded launchctl: \(path, privacy: .public)")
                } catch {
                    Logger.uninstaller.warning("launchctl unload failed '\(path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // 2. Move files to trash or remove permanently
        if bypassTrash {
            try safetyManager.validate(url: app.url)
            do {
                try fileManager.removeItem(at: app.url)
                Logger.uninstaller.info("Permanently removed: \(app.url.path, privacy: .public)")
            } catch {
                Logger.uninstaller.error("removeItem failed '\(app.url.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                throw error
            }

            for file in app.relatedFiles where file.isSelected {
                do {
                    try safetyManager.validate(url: file.url)
                    try fileManager.removeItem(at: file.url)
                    Logger.uninstaller.debug("Removed related: \(file.url.path, privacy: .public)")
                } catch {
                    Logger.uninstaller.warning("removeItem related '\(file.url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    // Non-fatal: continue with remaining related files
                }
            }
        } else {
            do {
                _ = try await trashManager.trashItem(at: app.url)
                Logger.uninstaller.info("Trashed: \(app.url.path, privacy: .public)")
            } catch {
                Logger.uninstaller.error("trashItem failed '\(app.url.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                throw error
            }

            for file in app.relatedFiles where file.isSelected {
                do {
                    _ = try await trashManager.trashItem(at: file.url)
                    Logger.uninstaller.debug("Trashed related: \(file.url.path, privacy: .public)")
                } catch {
                    Logger.uninstaller.warning("trashItem related '\(file.url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    // Non-fatal: continue with remaining related files
                }
            }
        }

        // 3. Forget package if applicable
        if let bundleID = app.bundleID {
            do {
                _ = try await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--forget", bundleID])
                Logger.uninstaller.debug("pkgutil --forget \(bundleID, privacy: .public)")
            } catch {
                Logger.uninstaller.warning("pkgutil --forget '\(bundleID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        // 4. Empty Trash immediately if requested
        if emptyTrashImmediately {
            do {
                try await trashManager.requestTrashAccess()
                _ = try await trashManager.emptyTrash()
            } catch {
                Logger.uninstaller.error("emptyTrash failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        Logger.uninstaller.info("Uninstall complete: '\(app.name, privacy: .public)'")
    }
}
