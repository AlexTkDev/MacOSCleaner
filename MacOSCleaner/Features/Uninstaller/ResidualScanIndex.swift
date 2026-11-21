import Foundation
import os

/// One-pass snapshot of standard ~/Library, /Library, Darwin, receipt, Homebrew, and /tmp roots
/// shared across all apps in a batch deep-scan to avoid O(apps × entries) filesystem re-enumeration.
public final class ResidualScanIndex: Sendable {
    public struct IndexedEntry: Sendable, Hashable {
        public let url: URL
        public let name: String
        public let lowerName: String
        public let parentName: String
        public let lowerParentName: String
        public let isDirectory: Bool
        public let isSymlink: Bool

        public init(
            url: URL,
            name: String,
            lowerName: String,
            parentName: String,
            lowerParentName: String,
            isDirectory: Bool,
            isSymlink: Bool
        ) {
            self.url = url
            self.name = name
            self.lowerName = lowerName
            self.parentName = parentName
            self.lowerParentName = lowerParentName
            self.isDirectory = isDirectory
            self.isSymlink = isSymlink
        }
    }

    public struct HomebrewAppEntry: Sendable {
        public let url: URL
        public let bundleIDLower: String?
    }

    public let baseDirectoryEntries: [String: [IndexedEntry]]
    public let allBaseEntries: [IndexedEntry]
    public let darwinEntries: [IndexedEntry]
    public let receiptEntries: [IndexedEntry]
    public let homeEntries: [IndexedEntry]
    public let homebrewAppsByLowerName: [String: [HomebrewAppEntry]]
    public let tmpTopLevelEntries: [IndexedEntry]
    /// `nil` when `pkgutil --pkgs` produced no packages or failed (e.g. mock test runners).
    public let pkgutilPackages: [String]?

    private let byExactLowerName: [String: [Int]]
    private let byTokenPrefix2: [String: [Int]]
    private let byTokenPrefix3: [String: [Int]]
    private let subdirectoryCache = OSAllocatedUnfairLock<[String: [IndexedEntry]]>(initialState: [:])
    private let pkgutilFilesCache = OSAllocatedUnfairLock<[String: [String]]>(initialState: [:])

    private static let tokenStopwords: Set<String> = [
        "com", "org", "net", "io", "app", "co", "dev", "ai",
        "uk", "de", "ru", "fr", "jp", "cn", "me", "tv", "gg", "sh",
        "us", "eu", "inc", "ltd", "llc", "apple"
    ]

    private init(
        baseDirectoryEntries: [String: [IndexedEntry]],
        allBaseEntries: [IndexedEntry],
        byExactLowerName: [String: [Int]],
        byTokenPrefix2: [String: [Int]],
        byTokenPrefix3: [String: [Int]],
        darwinEntries: [IndexedEntry],
        receiptEntries: [IndexedEntry],
        homeEntries: [IndexedEntry],
        homebrewAppsByLowerName: [String: [HomebrewAppEntry]],
        tmpTopLevelEntries: [IndexedEntry],
        pkgutilPackages: [String]?
    ) {
        self.baseDirectoryEntries = baseDirectoryEntries
        self.allBaseEntries = allBaseEntries
        self.byExactLowerName = byExactLowerName
        self.byTokenPrefix2 = byTokenPrefix2
        self.byTokenPrefix3 = byTokenPrefix3
        self.darwinEntries = darwinEntries
        self.receiptEntries = receiptEntries
        self.homeEntries = homeEntries
        self.homebrewAppsByLowerName = homebrewAppsByLowerName
        self.tmpTopLevelEntries = tmpTopLevelEntries
        self.pkgutilPackages = pkgutilPackages
    }

    /// Reads one directory in a single kernel pass (`getattrlistbulk` via `URLResourceValues`).
    public static func readDirectory(
        at dirURL: URL,
        options: FileManager.DirectoryEnumerationOptions = [],
        fileManager: FileManager = .default
    ) -> [IndexedEntry] {
        autoreleasepool {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: options
            ) else {
                return []
            }
            let parentName = dirURL.lastPathComponent
            let lowerParentName = parentName.lowercased()
            var entries: [IndexedEntry] = []
            entries.reserveCapacity(contents.count)
            for item in contents {
                let rv = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let isSymlink = rv?.isSymbolicLink == true
                let isDirectory = !isSymlink && (rv?.isDirectory == true)
                let name = item.lastPathComponent
                entries.append(IndexedEntry(
                    url: NormalizedPath.canonicalize(item),
                    name: name,
                    lowerName: name.lowercased(),
                    parentName: parentName,
                    lowerParentName: lowerParentName,
                    isDirectory: isDirectory,
                    isSymlink: isSymlink
                ))
            }
            return entries
        }
    }

    public static func build(
        fileSystemContext: FileSystemContext = .production,
        homebrewCellarDirectories: [URL] = AppDiscovery.defaultHomebrewCellarDirectories,
        darwinUserDirectories: [URL]? = nil,
        receiptsDirectory: URL? = nil,
        tmpScanDirectory: URL? = nil,
        commandRunner: any CommandRunning = CommandRunner(),
        fileManager: FileManager = .default
    ) async -> ResidualScanIndex {
        let home = fileSystemContext.homePath

        var baseDirs: [String] = CandidateCollector.basePaths(home: home)
        for relative in [".config", ".cache", ".local/share"] {
            baseDirs.append(NormalizedPath.joinHome(home, relative))
        }
        var seenBaseKeys = Set<String>()
        var uniqueBaseDirs: [URL] = []
        for path in baseDirs {
            let url = NormalizedPath.url(path, isDirectory: true)
            let key = NormalizedPath.key(url)
            if seenBaseKeys.insert(key).inserted {
                uniqueBaseDirs.append(url)
            }
        }

        let resolvedDarwinDirs: [URL]
        if let darwinUserDirectories {
            resolvedDarwinDirs = darwinUserDirectories
        } else {
            let parent = fileManager.temporaryDirectory
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
            resolvedDarwinDirs = ["C", "T", "X"].map {
                parent.appendingPathComponent($0, isDirectory: true)
            }
        }

        let resolvedReceiptsDir = (receiptsDirectory
            ?? URL(fileURLWithPath: "/private/var/db/receipts", isDirectory: true))
            .resolvingSymlinksInPath()
        let resolvedTmpDir = (tmpScanDirectory
            ?? URL(fileURLWithPath: "/private/tmp", isDirectory: true))
            .resolvingSymlinksInPath()

        async let pkgutilTask: [String]? = fetchPkgutilPackages(commandRunner: commandRunner)

        var baseDirectoryEntries: [String: [IndexedEntry]] = [:]
        baseDirectoryEntries.reserveCapacity(uniqueBaseDirs.count)
        var allBaseEntries: [IndexedEntry] = []

        for dirURL in uniqueBaseDirs {
            let key = NormalizedPath.key(dirURL)
            let entries = readDirectory(at: dirURL, options: [], fileManager: fileManager)
            baseDirectoryEntries[key] = entries
            if !entries.isEmpty {
                allBaseEntries.append(contentsOf: entries)
            }
        }

        var byExactLowerName: [String: [Int]] = [:]
        var byTokenPrefix2: [String: [Int]] = [:]
        var byTokenPrefix3: [String: [Int]] = [:]
        byExactLowerName.reserveCapacity(allBaseEntries.count)

        for idx in allBaseEntries.indices {
            let lowerName = allBaseEntries[idx].lowerName
            byExactLowerName[lowerName, default: []].append(idx)

            let bare = lowerName.hasPrefix(".") ? String(lowerName.dropFirst()) : lowerName
            let compactBare = EvidenceProbe.compactIdentityToken(bare)
            if compactBare.count >= 2 {
                byTokenPrefix2[String(compactBare.prefix(2)), default: []].append(idx)
            }
            if compactBare.count >= 3 {
                byTokenPrefix3[String(compactBare.prefix(3)), default: []].append(idx)
            }

            for token in alnumTokens(in: lowerName) {
                if token.count >= 2 {
                    byTokenPrefix2[String(token.prefix(2)), default: []].append(idx)
                }
                if token.count >= 3 {
                    byTokenPrefix3[String(token.prefix(3)), default: []].append(idx)
                }
            }
        }

        var darwinEntries: [IndexedEntry] = []
        for dir in resolvedDarwinDirs {
            darwinEntries.append(contentsOf: readDirectory(at: dir, options: [.skipsHiddenFiles], fileManager: fileManager))
        }

        let receiptEntries = readDirectory(at: resolvedReceiptsDir, options: [.skipsHiddenFiles], fileManager: fileManager)
        let homeURL = NormalizedPath.url(home, isDirectory: true)
        let homeEntries = readDirectory(at: homeURL, options: [], fileManager: fileManager)
        let homebrewApps = indexHomebrewApps(in: homebrewCellarDirectories, fileManager: fileManager)
        let tmpTopLevel = readDirectory(at: resolvedTmpDir, options: [.skipsHiddenFiles], fileManager: fileManager)
        let pkgutilPackages = await pkgutilTask

        return ResidualScanIndex(
            baseDirectoryEntries: baseDirectoryEntries,
            allBaseEntries: allBaseEntries,
            byExactLowerName: byExactLowerName,
            byTokenPrefix2: byTokenPrefix2,
            byTokenPrefix3: byTokenPrefix3,
            darwinEntries: darwinEntries,
            receiptEntries: receiptEntries,
            homeEntries: homeEntries,
            homebrewAppsByLowerName: homebrewApps,
            tmpTopLevelEntries: tmpTopLevel,
            pkgutilPackages: pkgutilPackages
        )
    }

    public func candidateBaseEntries(for identity: AppIdentity) -> [IndexedEntry] {
        var matchedIndices = Set<Int>()
        var needsFullFallback = false

        func addIndices(_ indices: [Int]?) {
            guard let indices else { return }
            matchedIndices.formUnion(indices)
        }

        func addPrefixLookup(forToken token: String) {
            if token.count >= 3 {
                addIndices(byTokenPrefix3[String(token.prefix(3))])
            } else if token.count == 2 {
                addIndices(byTokenPrefix2[token])
            } else if token.count == 1 {
                needsFullFallback = true
            }
        }

        func addTermLookup(_ rawTerm: String) {
            let lower = rawTerm.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lower.isEmpty else { return }
            addIndices(byExactLowerName[lower])
            addIndices(byExactLowerName["." + lower])

            let compact = EvidenceProbe.compactIdentityToken(lower)
            if !compact.isEmpty {
                addPrefixLookup(forToken: compact)
            }

            let tokens = Self.alnumTokens(in: lower)
            if let first = tokens.first {
                addPrefixLookup(forToken: first)
            }
            for token in tokens where token.count >= 2 && !Self.tokenStopwords.contains(token) {
                addPrefixLookup(forToken: token)
            }
        }

        let lowerBundleID = identity.bundleID.lowercased()
        if !lowerBundleID.isEmpty, !lowerBundleID.hasPrefix("unknown.") {
            addIndices(byExactLowerName[lowerBundleID])
            let bidTokens = Self.alnumTokens(in: lowerBundleID)
            let significant = bidTokens.filter { !Self.tokenStopwords.contains($0) }
            let queryTokens = significant.isEmpty ? bidTokens : significant
            if queryTokens.contains(where: { $0.count < 2 }) || queryTokens.isEmpty {
                needsFullFallback = true
            } else {
                for token in queryTokens {
                    addPrefixLookup(forToken: token)
                }
            }
        }

        addTermLookup(identity.appName)
        if let bundleName = identity.bundleName, !bundleName.isEmpty {
            addTermLookup(bundleName)
        }
        if !identity.executableName.isEmpty {
            addTermLookup(identity.executableName)
        }

        if let teamID = identity.teamID, !teamID.isEmpty {
            addPrefixLookup(forToken: teamID.lowercased())
        }

        for group in identity.appGroups where !group.isEmpty {
            addIndices(byExactLowerName[group.lowercased()])
        }

        for helper in identity.helperNames {
            let helperLower = helper.lowercased()
            guard helperLower.count >= 3 else { continue }
            addIndices(byExactLowerName[helperLower])
            let compactHelper = EvidenceProbe.compactIdentityToken(helperLower)
            if compactHelper.count >= 2 {
                addPrefixLookup(forToken: compactHelper)
            }
            if let first = Self.alnumTokens(in: helperLower).first {
                addPrefixLookup(forToken: first)
            }
        }

        for vendor in identity.vendorNames where !vendor.isEmpty {
            addIndices(byExactLowerName[vendor.lowercased()])
        }

        if needsFullFallback {
            return allBaseEntries
        }
        return matchedIndices.map { allBaseEntries[$0] }
    }

    public func entries(
        inDirectory dirURL: URL,
        options: FileManager.DirectoryEnumerationOptions = [],
        fileManager: FileManager = .default
    ) -> [IndexedEntry] {
        let key = NormalizedPath.key(dirURL)
        if let base = baseDirectoryEntries[key] {
            if options.contains(.skipsHiddenFiles) {
                return base.filter { !$0.name.hasPrefix(".") }
            }
            return base
        }

        let cacheKey = options.contains(.skipsHiddenFiles) ? "\(key)|nh" : key
        if let cached = subdirectoryCache.withLock({ $0[cacheKey] }) {
            return cached
        }

        let loaded = Self.readDirectory(at: dirURL, options: options, fileManager: fileManager)
        subdirectoryCache.withLock { cache in
            if cache.count < 4096 {
                cache[cacheKey] = loaded
            }
        }
        return loaded
    }

    public func pkgutilFiles(for packageID: String, commandRunner: any CommandRunning) async -> [String] {
        if let cached = pkgutilFilesCache.withLock({ $0[packageID] }) {
            return cached
        }
        guard let result = try? await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--files", packageID]),
              result.exitCode == 0 else {
            pkgutilFilesCache.withLock { $0[packageID] = [] }
            return []
        }
        let files = result.stdout.split(whereSeparator: \.isNewline).map(String.init)
        pkgutilFilesCache.withLock { cache in
            if cache.count < 1024 {
                cache[packageID] = files
            }
        }
        return files
    }

    private static func alnumTokens(in string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in string {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func fetchPkgutilPackages(commandRunner: any CommandRunning) async -> [String]? {
        guard let result = try? await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--pkgs"]),
              result.exitCode == 0 else {
            return nil
        }
        let packages = result.stdout.split(whereSeparator: \.isNewline).map(String.init)
        return packages.isEmpty ? nil : packages
    }

    private static func indexHomebrewApps(
        in cellarDirectories: [URL],
        fileManager: FileManager
    ) -> [String: [HomebrewAppEntry]] {
        guard !cellarDirectories.isEmpty else { return [:] }
        var map: [String: [HomebrewAppEntry]] = [:]
        autoreleasepool {
            for cellar in cellarDirectories {
                guard let formulae = try? fileManager.contentsOfDirectory(
                    at: cellar,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for formula in formulae {
                    guard let versions = try? fileManager.contentsOfDirectory(
                        at: formula,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for version in versions {
                        guard let apps = try? fileManager.contentsOfDirectory(
                            at: version,
                            includingPropertiesForKeys: [.isDirectoryKey],
                            options: [.skipsHiddenFiles]
                        ) else { continue }
                        for app in apps {
                            let lowerName = app.lastPathComponent.lowercased()
                            guard lowerName.hasSuffix(".app") else { continue }
                            let resolved = app.resolvingSymlinksInPath()
                            let bid = Bundle(url: resolved)?.bundleIdentifier?.lowercased()
                            map[lowerName, default: []].append(HomebrewAppEntry(url: resolved, bundleIDLower: bid))
                        }
                    }
                }
            }
        }
        return map
    }
}
