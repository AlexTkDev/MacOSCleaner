import Foundation
import AppKit
import ApplicationServices
import CoreServices

public actor AppDiscovery {
    public static let defaultHomebrewCellarDirectories = [
        URL(fileURLWithPath: "/opt/homebrew/Cellar", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/Cellar", isDirectory: true),
    ]

    private let fileManager: FileManager
    private let commandRunner: CommandRunner
    private let homebrewCellarDirectories: [URL]

    public init(
        fileManager: FileManager = .default,
        commandRunner: CommandRunner = CommandRunner(),
        homebrewCellarDirectories: [URL] = AppDiscovery.defaultHomebrewCellarDirectories
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.homebrewCellarDirectories = homebrewCellarDirectories
    }

    public func findAll() async -> [URL] {
        var urls: [URL] = []

        // Standard app directories
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: "\(NSHomeDirectory())/Applications"),
        ].compactMap { $0 }

        for dir in appDirs {
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
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        }

        // Dev build products (DerivedData)
        let derivedData = "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData"
        if let result = try? await commandRunner.run(
            command: "/usr/bin/find",
            arguments: [derivedData, "-maxdepth", "5", "-name", "*.app", "-type", "d", "-prune"]
        ) {
            for path in result.stdout.components(separatedBy: .newlines) where !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                if !url.path.contains("/Applications/") {
                    urls.append(url)
                }
            }
        }

        return Array(Set(urls)).filter { !Self.isUndeletableSystemApp($0) }
    }

    /// Top-level `.app` plus one nested level (e.g. `/Applications/Utilities/*.app`).
    static func applicationBundles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let contents = directoryContents(at: directory, fileManager: fileManager) else { return [] }
        var apps: [URL] = []
        for item in contents {
            if item.pathExtension.lowercased() == "app", isDirectory(item) {
                apps.append(item)
                continue
            }
            guard isDirectory(item),
                  let nested = directoryContents(at: item, fileManager: fileManager)
            else { continue }
            for child in nested where child.pathExtension.lowercased() == "app" && isDirectory(child) {
                apps.append(child)
            }
        }
        return apps
    }

    /// Apps that cannot be uninstalled: anything under `/System` (including
    /// `/Applications` symlinks into Cryptexes), plus Apple components outside `/Applications`.
    static func isUndeletableSystemApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        if path.hasPrefix("/System/") || resolved.hasPrefix("/System/") {
            return true
        }
        // `/Applications/Safari.app` → Cryptex already caught above via resolved path.
        guard !path.hasPrefix("/Applications/") else { return false }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return false }
        return bundleID.hasPrefix("com.apple.")
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

    static func homebrewFormulaApplications(
        containing bundleURL: URL,
        cellarDirectories: [URL] = defaultHomebrewCellarDirectories,
        fileManager: FileManager = .default
    ) -> Set<URL> {
        guard let location = homebrewFormulaLocation(
            containing: bundleURL,
            cellarDirectories: cellarDirectories
        ), let formulae = directoryContents(at: location.cellar, fileManager: fileManager) else {
            return []
        }

        let familyName = homebrewFormulaFamilyName(location.formulaName)
        var applications = Set<URL>()
        for formula in formulae where isDirectory(formula)
            && homebrewFormulaFamilyName(formula.lastPathComponent) == familyName {
            applications.formUnion(homebrewApplications(
                inFormulaRoot: formula,
                fileManager: fileManager
            ))
        }
        return applications
    }

    private static func homebrewFormulaLocation(
        containing bundleURL: URL,
        cellarDirectories: [URL]
    ) -> (cellar: URL, formulaName: String)? {
        let bundlePath = bundleURL.standardizedFileURL.path
        for cellar in cellarDirectories {
            let cellarPath = cellar.standardizedFileURL.path
            let prefix = cellarPath + "/"
            guard bundlePath.hasPrefix(prefix) else { continue }
            let relativePath = String(bundlePath.dropFirst(prefix.count))
            guard let formulaName = relativePath.split(separator: "/").first else { continue }
            return (cellar, String(formulaName))
        }
        return nil
    }

    private static func homebrewFormulaFamilyName(_ formulaName: String) -> String {
        String(formulaName.split(separator: "@", maxSplits: 1).first ?? Substring(formulaName))
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

}
