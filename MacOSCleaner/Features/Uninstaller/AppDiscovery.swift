import Foundation
import AppKit
import ApplicationServices
import CoreServices

public actor AppDiscovery {
    public static let defaultHomebrewCellarDirectories = [
        NormalizedPath.url("/opt/homebrew/Cellar", isDirectory: true),
        NormalizedPath.url("/usr/local/Cellar", isDirectory: true),
    ]

    private let fileManager: FileManager
    private let commandRunner: CommandRunner
    private let homebrewCellarDirectories: [URL]
    private let customSearchDirectories: [URL]?
    private let customExternalVolumesRoot: URL?

    public init(
        fileManager: FileManager = .default,
        commandRunner: CommandRunner = CommandRunner(),
        homebrewCellarDirectories: [URL] = AppDiscovery.defaultHomebrewCellarDirectories,
        searchDirectories: [URL]? = nil,
        externalVolumesRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.homebrewCellarDirectories = homebrewCellarDirectories
        self.customSearchDirectories = searchDirectories
        self.customExternalVolumesRoot = externalVolumesRoot
    }

    public func findAll() async -> [URL] {
        var urls: [URL] = []

        if let customSearchDirectories {
            for dir in customSearchDirectories {
                urls.append(contentsOf: Self.applicationBundles(in: dir, fileManager: fileManager))
            }
            if let customExternalVolumesRoot {
                for dir in Self.externalVolumeApplicationDirectories(fileManager: fileManager, volumesRoot: customExternalVolumesRoot) {
                    urls.append(contentsOf: Self.applicationBundles(in: dir, fileManager: fileManager))
                }
            }
            urls.append(contentsOf: Self.homebrewApplications(
                in: homebrewCellarDirectories,
                fileManager: fileManager
            ))
            return NormalizedPath.unique(urls).filter { !Self.isUndeletableSystemApp($0) }
        }

        // Standard app directories
        let appDirs = [
            NormalizedPath.url("/Applications", isDirectory: true),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first.map { NormalizedPath.url($0) },
            NormalizedPath.url(NormalizedPath.joinHome(NSHomeDirectory(), "Applications"), isDirectory: true),
        ].compactMap { $0 }

        for dir in appDirs {
            urls.append(contentsOf: Self.applicationBundles(in: dir, fileManager: fileManager))
        }

        // Mounted local writable external volumes (e.g. macOS App Store external SSD installs
        // at /Volumes/<SSD>/Applications). Skips network shares, read-only DMGs, and Time Machine.
        for dir in Self.externalVolumeApplicationDirectories(fileManager: fileManager, volumesRoot: customExternalVolumesRoot) {
            urls.append(contentsOf: Self.applicationBundles(in: dir, fileManager: fileManager))
        }

        // Homebrew formulae can expose user-facing apps directly inside a keg
        // (for example python@3.x/3.x.y/IDLE 3.app). Scan only the fixed
        // Cellar/formula/version/*.app shape; never recurse through formula contents.
        urls.append(contentsOf: Self.homebrewApplications(
            in: homebrewCellarDirectories,
            fileManager: fileManager
        ))

        // LaunchServices sees apps registered outside the usual filesystem roots.
        urls.append(contentsOf: Self.launchServicesApplications())

        // Application Support (Google Updater, etc.)
        let appSupportDirs = [
            "\(NSHomeDirectory())/Library/Application Support",
            "/Library/Application Support"
        ]

        for appSupport in appSupportDirs {
            if let result = try? await commandRunner.run(
                command: "/usr/bin/find",
                arguments: [appSupport, "-maxdepth", "4", "-name", "*.app", "-type", "d", "-prune"]
            ) {
                for path in result.stdout.components(separatedBy: .newlines) where !path.isEmpty {
                    urls.append(NormalizedPath.url(path))
                }
            }
        }

        // Dev build products (DerivedData)
        let derivedData = NormalizedPath.joinHome(NSHomeDirectory(), "Library/Developer/Xcode/DerivedData")
        if let result = try? await commandRunner.run(
            command: "/usr/bin/find",
            arguments: [derivedData, "-maxdepth", "5", "-name", "*.app", "-type", "d", "-prune"]
        ) {
            for path in result.stdout.components(separatedBy: .newlines) where !path.isEmpty {
                let url = NormalizedPath.url(path)
                if !url.path.contains("/Applications/") {
                    urls.append(url)
                }
            }
        }

        return NormalizedPath.unique(urls).filter { !Self.isUndeletableSystemApp($0) }
    }

    /// Discovers `<ExternalVolume>/Applications` directories on mounted local, writable,
    /// browsable non-root volumes (skips read-only DMG installers, SMB/NFS shares, Time Machine).
    static func externalVolumeApplicationDirectories(
        fileManager: FileManager = .default,
        volumesRoot: URL? = nil
    ) -> [URL] {
        var result: [URL] = []

        if let volumesRoot {
            guard let volumes = directoryContents(at: volumesRoot, fileManager: fileManager) else {
                return []
            }
            for volume in volumes where isDirectory(volume) {
                guard SafetyManager.isAllowedExternalVolumeName(volume.lastPathComponent) else { continue }
                let appsDir = volume.appendingPathComponent("Applications", isDirectory: true)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: appsDir.path, isDirectory: &isDir), isDir.boolValue {
                    result.append(NormalizedPath.url(appsDir.path, isDirectory: true))
                }
            }
            return result
        }

        let keys: [URLResourceKey] = [
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey,
            .volumeIsBrowsableKey,
            .volumeIsRootFileSystemKey,
        ]
        guard let mountedVolumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        for volume in mountedVolumes {
            guard let values = try? volume.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.volumeIsRootFileSystem != true else { continue }
            guard values.volumeIsLocal == true else { continue }
            guard values.volumeIsReadOnly != true else { continue }
            guard values.volumeIsBrowsable != false else { continue }
            guard SafetyManager.isAllowedExternalVolumeName(volume.lastPathComponent) else { continue }

            let appsDir = volume.appendingPathComponent("Applications", isDirectory: true)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: appsDir.path, isDirectory: &isDir), isDir.boolValue {
                result.append(NormalizedPath.url(appsDir.path, isDirectory: true))
            }
        }
        return result
    }

    /// Top-level `.app` (including valid symlinks to `.app` bundles on external SSDs)
    /// plus one nested level (e.g. `/Applications/Utilities/*.app`).
    static func applicationBundles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let contents = directoryContents(at: directory, fileManager: fileManager) else { return [] }
        var apps: [URL] = []
        for item in contents {
            if item.pathExtension.lowercased() == "app", isAppDirectory(item, fileManager: fileManager) {
                apps.append(item)
                continue
            }
            guard isDirectory(item),
                  let nested = directoryContents(at: item, fileManager: fileManager)
            else { continue }
            for child in nested where child.pathExtension.lowercased() == "app" && isAppDirectory(child, fileManager: fileManager) {
                apps.append(child)
            }
        }
        return apps
    }

    /// Apps that cannot be uninstalled: `/System` (incl. Cryptex), nested Apple
    /// components (e.g. inside Xcode.app), and `com.apple.dt.*` satellites except Xcode.
    static func isUndeletableSystemApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        if path.hasPrefix("/System/") || resolved.hasPrefix("/System/") {
            return true
        }

        let bundleID = Bundle(url: url)?.bundleIdentifier
        if let bundleID {
            let lower = bundleID.lowercased()
            // Xcode satellites (ExternalViewService, SourceKit, …) — never list.
            if lower.hasPrefix("com.apple.dt."), lower != "com.apple.dt.xcode" {
                return true
            }
            if lower.hasPrefix("com.apple.") {
                return !isTopLevelUserApplication(path)
            }
        }
        return false
    }

    /// `/Applications/Foo.app`, `/Applications/Utilities/Foo.app`, or `~/Applications/Foo.app`.
    /// Nested bundles (`Foo.app/Contents/.../Bar.app`) are not top-level.
    static func isTopLevelUserApplication(_ path: String) -> Bool {
        let url = NormalizedPath.url(path)
        guard url.pathExtension.lowercased() == "app" else { return false }
        let appSegments = url.pathComponents.filter { $0.lowercased().hasSuffix(".app") }
        guard appSegments.count == 1 else { return false }

        let parent = url.deletingLastPathComponent()
        if parent.path == "/Applications" { return true }
        if parent.lastPathComponent == "Utilities",
           parent.deletingLastPathComponent().path == "/Applications" {
            return true
        }
        return parent.lastPathComponent == "Applications"
    }

    /// Sidebar-listable: real `.app` with a CFBundleIdentifier (excludes CLI/`unknown.*`).
    static func isListableApplication(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else { return false }
        guard !bundleID.lowercased().hasPrefix("unknown.") else { return false }
        return !isUndeletableSystemApp(url)
    }

    static func homebrewApplications(
        in cellarDirectories: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        var applications = Set<URL>()
        for cellar in cellarDirectories {
            guard let formulae = directoryContents(at: cellar, fileManager: fileManager) else { continue }
            for formula in formulae where isDirectory(formula) {
                applications.formUnion(homebrewApplications(
                    inFormulaRoot: formula,
                    fileManager: fileManager
                ))
            }
        }
        return applications.sorted { $0.path < $1.path }
    }

    private static func homebrewApplications(
        inFormulaRoot formulaRoot: URL,
        fileManager: FileManager
    ) -> Set<URL> {
        guard let versions = directoryContents(at: formulaRoot, fileManager: fileManager) else {
            return []
        }

        var applications = Set<URL>()
        for version in versions where isDirectory(version) {
            let receipt = version.appendingPathComponent("INSTALL_RECEIPT.json")
            guard fileManager.fileExists(atPath: receipt.path),
                  let contents = directoryContents(at: version, fileManager: fileManager)
            else {
                continue
            }
            for item in contents where item.pathExtension.lowercased() == "app" && isDirectory(item) {
                applications.insert(item)
            }
        }
        return applications
    }

    private static func launchServicesApplications() -> [URL] {
        // Public SDK has no LSCopyAllApplicationURLs. Directory scan in findAll() covers
        // /Applications and ~/Applications; running apps are an extra signal.
        Array(Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)))
    }

    private static func directoryContents(at url: URL, fileManager: FileManager) -> [URL]? {
        try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// True for a real `.app` bundle directory OR a valid symlink resolving to an existing directory
    /// (e.g. an app offloaded to an external SSD and symlinked into `/Applications`).
    /// Broken symlinks (unplugged drive) return `false`.
    private static func isAppDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        if isDirectory(url) { return true }
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

}
