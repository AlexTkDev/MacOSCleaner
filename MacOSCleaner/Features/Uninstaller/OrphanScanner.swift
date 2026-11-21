import Foundation
import OSLog

private extension Logger {
    static let orphanScanner = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "OrphanScanner")
}

public struct OrphanItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let sizeBytes: Int64
    public let category: String
    public let modificationDate: Date?
    public let evidence: Set<Evidence>
    public let confidence: ConfidenceTier
    public let score: Int
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        bundleID: String?,
        sizeBytes: Int64,
        category: String,
        modificationDate: Date? = nil,
        evidence: Set<Evidence> = [],
        confidence: ConfidenceTier = .possible,
        score: Int = 0,
        isSelected: Bool = true
    ) {
        self.id = id
        self.url = NormalizedPath.canonicalize(url)
        self.name = name
        self.bundleID = bundleID
        self.sizeBytes = sizeBytes
        self.category = category
        self.modificationDate = modificationDate
        self.evidence = evidence
        self.confidence = confidence
        self.score = score
        self.isSelected = isSelected
    }

    public static func localizedCategoryName(for category: String) -> String {
        switch category {
        case "Caches": return "uninstaller_orphan_cat_caches".localized
        case "Preferences": return "uninstaller_orphan_cat_preferences".localized
        case "Application Support": return "uninstaller_orphan_cat_app_support".localized
        case "Logs": return "uninstaller_orphan_cat_logs".localized
        case "Containers": return "uninstaller_orphan_cat_containers".localized
        case "Developer": return "uninstaller_orphan_cat_developer".localized
        case "Launch Agents", "LaunchAgents": return "uninstaller_orphan_cat_launch_agents".localized
        case "Other": return "uninstaller_orphan_cat_other".localized
        default: return category
        }
    }

    public var localizedCategory: String {
        Self.localizedCategoryName(for: category)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(NormalizedPath.key(url))
    }

    public static func == (lhs: OrphanItem, rhs: OrphanItem) -> Bool {
        NormalizedPath.key(lhs.url) == NormalizedPath.key(rhs.url) && lhs.isSelected == rhs.isSelected
    }
}

public actor OrphanScanner {
    private let safetyManager: SafetyManager
    private let commandRunner: CommandRunner
    private let fileSystemContext: FileSystemContext
    private let appDiscovery: AppDiscovery
    private let codesignCache: CodesignCache
    private let plistCache: PlistContentCache
    private let ruleRegistry: ApplicationRuleRegistry
    private let homebrewCellarDirectories: [URL]
    private let fileManager = FileManager.default

    public init(
        safetyManager: SafetyManager,
        commandRunner: CommandRunner = CommandRunner(),
        fileSystemContext: FileSystemContext = .production,
        codesignCache: CodesignCache = CodesignCache(),
        plistCache: PlistContentCache = PlistContentCache(),
        ruleRegistry: ApplicationRuleRegistry = .shared,
        appDiscovery: AppDiscovery? = nil,
        homebrewCellarDirectories: [URL] = AppDiscovery.defaultHomebrewCellarDirectories
    ) {
        self.safetyManager = safetyManager
        self.commandRunner = commandRunner
        self.fileSystemContext = fileSystemContext
        self.appDiscovery = appDiscovery ?? AppDiscovery(
            commandRunner: commandRunner,
            homebrewCellarDirectories: homebrewCellarDirectories
        )
        self.codesignCache = codesignCache
        self.plistCache = plistCache
        self.ruleRegistry = ruleRegistry
        self.homebrewCellarDirectories = homebrewCellarDirectories
    }

    public func scanOrphans(progress: (@Sendable (String) -> Void)? = nil) async throws -> [OrphanItem] {
        try Task.checkCancellation()
        progress?("uninstaller.progress.discovering".localized)
        
        // 1. Discover installed apps & Homebrew formulae
        let installedURLs = await appDiscovery.findAll()
        let runner = commandRunner
        let identities = (try? await UninstallerService.mapWithBoundedConcurrency(
            items: installedURLs,
            maxConcurrent: UninstallerService.maxConcurrentDiscoveryTasks
        ) { url in
            await AppIdentity.resolve(from: url, commandRunner: runner)
        }) ?? []
        let installedHomebrewFormulae = collectInstalledHomebrewFormulae()
        
        try Task.checkCancellation()
        progress?("uninstaller_orphan_scanning_dirs".localized)
        
        // 2. Collect ALL files from scan directories
        let allFiles = await collectAllScanTargets()
        
        progress?(String(format: "uninstaller_orphan_analyzing_count".localized, Int64(allFiles.count)))
        let probe = EvidenceProbe(
            commandRunner: commandRunner,
            codesignCache: codesignCache,
            plistCache: plistCache
        )
        
        var orphans: [OrphanItem] = []
        var processed = 0
        let total = allFiles.count
        var commandExistsCache: [String: Bool] = [:]
        
        for file in allFiles {
            try Task.checkCancellation()
            processed += 1
            if processed % 100 == 0 {
                progress?(String(format: "uninstaller_orphan_analyzing_progress".localized, Int64(processed), Int64(total)))
            }
            
            // Basic safety & size filters
            guard (try? safetyManager.validate(url: file, policy: .uninstall)) != nil else { continue }
            
            // Skip Apple system items, system daemons, and developer toolchain containers
            if Self.isSystemOrProtected(file: file) {
                continue
            }
            
            let isOwned = await checkOwnership(
                file: file,
                identities: identities,
                probe: probe,
                installedHomebrewFormulae: installedHomebrewFormulae,
                commandExistsCache: &commandExistsCache
            )
            
            if !isOwned {
                let size = fileManager.getPhysicalDirectorySize(url: file)
                // Filter small orphans unless they are plists or configs
                let ext = file.pathExtension.lowercased()
                let isConfig = ["plist", "json", "yaml", "xml", "conf"].contains(ext)
                if size < 4 * 1024 && !isConfig {
                    continue
                }
                
                let modDate = (try? fileManager.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
                
                // Determine category from path
                let pathStr = file.path
                var category = "Other"
                if pathStr.contains("/Caches/") { category = "Caches" }
                else if pathStr.contains("/Preferences/") { category = "Preferences" }
                else if pathStr.contains("/Application Support/") { category = "Application Support" }
                else if pathStr.contains("/Logs/") { category = "Logs" }
                else if pathStr.contains("/Containers/") || pathStr.contains("/Group Containers/") { category = "Containers" }
                else if pathStr.contains("/LaunchAgents/") || pathStr.contains("/LaunchDaemons/") { category = "Launch Agents" }
                else if pathStr.contains("/Developer/") || pathStr.contains("CommandLineTools") { category = "Developer" }
                
                let extracted = Self.extractBundleIDAndName(from: file)
                
                // Generic folders without any bundle ID or specific orphan markers are not orphans
                if extracted.bundleID == nil {
                    let ext = file.pathExtension.lowercased()
                    let isSpecialResidual = ext == "savedstate" || ext == "plist" || pathStr.contains("/Containers/") || pathStr.contains("/Group Containers/")
                    if !isSpecialResidual {
                        continue
                    }
                }

                let (evidence, score, tier) = await collectOrphanEvidence(
                    for: file,
                    bundleID: extracted.bundleID,
                    name: extracted.name,
                    probe: probe
                )

                // Enforce confidence threshold: require at least veryLikely for standalone leftovers
                guard tier >= .veryLikely, !evidence.isEmpty else {
                    continue
                }

                orphans.append(OrphanItem(
                    url: file,
                    name: extracted.name,
                    bundleID: extracted.bundleID,
                    sizeBytes: size,
                    category: category,
                    modificationDate: modDate,
                    evidence: evidence,
                    confidence: tier,
                    score: score,
                    isSelected: true
                ))
                Logger.orphanScanner.debug("Found orphan: \(extracted.name, privacy: .public) (\(size) bytes) tier=\(tier.rawValue) bundleID=\(extracted.bundleID ?? "nil")")
            }
        }
        
        return orphans.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func isSystemOrProtected(file: URL) -> Bool {
        let rawFilename = file.lastPathComponent.lowercased()
        let filename = Self.stripTeamIDPrefix(from: rawFilename)
            .replacingOccurrences(of: "group.", with: "")
            .replacingOccurrences(of: "groups.", with: "")

        let protectedPrefixes = [
            "com.apple.",
            "com.mac.",
            "is.workflow.",
            "org.swift.",
            "org.llvm.",
            "org.gnu.",
            "org.cups.",
            "org.sparkle-project.",
            "org.openldap.",
            "org.apache.",
            "tvappservices.",
            "com.crashlytics.",
            "io.fabric."
        ]

        // Shared telemetry/crash SDKs and updaters have no standalone .app bundle.
        let protectedSharedSDKs = [
            "io.sentry",
            "com.plausiblelabs.crashreporter",
            "com.google.keystone",
            "sentrycrash"
        ]

        // Apple system containers, groups, daemons and system tools
        if rawFilename.contains("com.apple.") ||
           rawFilename.contains(".apple.") ||
           rawFilename.contains("group.com.apple") ||
           rawFilename.contains("groups.com.apple") ||
           protectedPrefixes.contains(where: { filename.hasPrefix($0) }) ||
           protectedSharedSDKs.contains(where: { filename == $0 || filename.hasPrefix("\($0).") }) {
            return true
        }

        return false
    }

    private static func stripTeamIDPrefix(from string: String) -> String {
        let pattern = #"^[A-Z0-9]{10}\.(?:groups?\.)?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: string.utf16.count)
            return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
        }
        return string
    }

    private func collectInstalledHomebrewFormulae() -> Set<String> {
        var formulae = Set<String>()
        var dirsToScan: [URL] = []
        for cellar in homebrewCellarDirectories {
            dirsToScan.append(cellar)
            let optSibling = cellar.deletingLastPathComponent().appendingPathComponent("opt", isDirectory: true)
            dirsToScan.append(optSibling)
        }
        for dir in dirsToScan {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in contents {
                let name = entry.lastPathComponent.lowercased()
                if !name.isEmpty {
                    formulae.insert(name)
                }
            }
        }
        return formulae
    }

    static func extractLaunchdExecutablePaths(from plistURL: URL) -> [String] {
        autoreleasepool {
            guard let data = try? Data(contentsOf: plistURL),
                  let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                return []
            }
            var candidates: [String] = []
            if let program = dict["Program"] as? String, !program.isEmpty {
                candidates.append(program)
            }
            if let args = dict["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty {
                let wrappers: Set<String> = [
                    "/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env",
                    "/usr/bin/java", "/opt/homebrew/bin/brew", "/usr/local/bin/brew"
                ]
                if !wrappers.contains(first) {
                    candidates.append(first)
                }
                for arg in args.dropFirst() where arg.hasPrefix("/") {
                    if !arg.hasPrefix("/bin/") && !arg.hasPrefix("/usr/bin/") && !arg.hasPrefix("/System/") {
                        candidates.append(arg)
                    }
                }
            }
            return candidates
        }
    }

    private func cachedCommandExists(_ toolName: String, cache: inout [String: Bool]) async -> Bool {
        if let cached = cache[toolName] { return cached }
        let quickPaths = [
            "/opt/homebrew/bin/\(toolName)",
            "/usr/local/bin/\(toolName)",
            "/usr/bin/\(toolName)",
            "/bin/\(toolName)"
        ]
        if quickPaths.contains(where: { fileManager.isExecutableFile(atPath: $0) }) {
            cache[toolName] = true
            return true
        }
        let exists = await commandRunner.commandExists(toolName)
        cache[toolName] = exists
        return exists
    }
    
    private func checkOwnership(
        file: URL,
        identities: [AppIdentity],
        probe: EvidenceProbe,
        installedHomebrewFormulae: Set<String>,
        commandExistsCache: inout [String: Bool]
    ) async -> Bool {
        let rawFilename = file.lastPathComponent.lowercased()
        let filename = Self.stripTeamIDPrefix(from: rawFilename)
            .replacingOccurrences(of: "group.", with: "")
            .replacingOccurrences(of: "groups.", with: "")
        let path = file.path.lowercased()
        let cleanName = (filename as NSString).deletingPathExtension.lowercased()

        // 0. Homebrew / CLI service LaunchAgents & LaunchDaemons (formulae have no .app bundle)
        if path.contains("/launchagents/") || path.contains("/launchdaemons/") {
            if (rawFilename.hasPrefix("homebrew.mxcl.") || rawFilename.hasPrefix("homebrew.cask.")),
               rawFilename.hasSuffix(".plist") {
                let prefixLen = rawFilename.hasPrefix("homebrew.mxcl.")
                    ? "homebrew.mxcl.".count
                    : "homebrew.cask.".count
                let formulaName = String(rawFilename.dropFirst(prefixLen).dropLast(".plist".count))
                if !formulaName.isEmpty, installedHomebrewFormulae.contains(formulaName) {
                    return true
                }
                let execPaths = Self.extractLaunchdExecutablePaths(from: file)
                if execPaths.contains(where: { fileManager.fileExists(atPath: $0) }) {
                    return true
                }
            } else if rawFilename.hasSuffix(".plist") {
                let cliPrefixes = [
                    "/opt/homebrew/", "/usr/local/cellar/", "/usr/local/opt/",
                    "/opt/local/", "/nix/", "/.nix-profile/"
                ]
                let execPaths = Self.extractLaunchdExecutablePaths(from: file)
                if execPaths.contains(where: { exec in
                    let lowerExec = exec.lowercased()
                    return cliPrefixes.contains(where: { lowerExec.contains($0) })
                        && fileManager.fileExists(atPath: exec)
                }) {
                    return true
                }
            }
        }

        // 1. Direct identity matching: app name, bundle ID, vendor names
        for identity in identities {
            let bid = identity.bundleID.lowercased()
            let appName = identity.appName.lowercased()
            
            // Exact name or clean name match
            if !appName.isEmpty {
                if cleanName == appName || filename == appName || rawFilename == appName {
                    return true
                }
                // Check if directory is a vendor suite folder matching app name
                if cleanName.count >= 2 && (appName.hasPrefix(cleanName + " ") || appName.hasSuffix(" " + cleanName)) {
                    return true
                }
                let appTokens = appName.components(separatedBy: CharacterSet(charactersIn: " -_.")).filter { $0.count >= 2 }
                for token in appTokens {
                    if EvidenceProbe.wordBoundaryMatch(cleanName, token) || EvidenceProbe.wordBoundaryMatch(filename, token) {
                        return true
                    }
                }
            }
            
            // Bundle ID match
            if !bid.isEmpty && bid.contains(".") {
                if cleanName == bid || filename == bid || path.contains(bid) {
                    return true
                }
                // Sub-bundle match: e.g. com.spotify.client.helper for com.spotify.client
                if cleanName.hasPrefix(bid + ".") || bid.hasPrefix(cleanName + ".") {
                    return true
                }
                
                // Match reverse DNS vendor part (e.g. com.google, com.microsoft, dev.orbstack)
                let parts = bid.components(separatedBy: ".")
                if parts.count >= 2 {
                    let domainPrefix = parts.prefix(2).joined(separator: ".")
                    if cleanName == domainPrefix || cleanName.hasPrefix(domainPrefix + ".") {
                        return true
                    }
                }
            }
            
            // Vendor names match (e.g. "Google", "Microsoft", "Adobe", "JetBrains")
            for vendor in identity.vendorNames {
                let v = vendor.lowercased()
                if v.count >= 3 {
                    if cleanName == v || filename == v || cleanName.contains(".\(v).") || cleanName.hasPrefix("com.\(v).") || cleanName.hasPrefix("org.\(v).") || cleanName.hasPrefix("io.\(v).") || cleanName.hasPrefix("\(v).") {
                        return true
                    }
                }
            }
        }

        // 2. Dot-files/tools check (e.g. ~/.gradle, ~/.npm, ~/.docker) - if command exists on system, it's not an orphan
        if filename.hasPrefix(".") {
            let toolName = String(filename.dropFirst())
            if !toolName.isEmpty {
                if await cachedCommandExists(toolName, cache: &commandExistsCache) {
                    return true
                }
            }
        }

        if cleanName.contains("java") || cleanName.contains("openjdk") {
            if await cachedCommandExists("java", cache: &commandExistsCache) {
                return true
            }
        }
        
        // 3. Priority probe check
        let priorityApps = identities.filter { identity in
            let bid = identity.bundleID.lowercased()
            let appName = identity.appName.lowercased()
            return (!bid.isEmpty && path.contains(bid)) || (!appName.isEmpty && cleanName == appName)
        }
        
        for identity in priorityApps {
            let evidence = await probe.probe(url: file, identity: identity)
            guard !evidence.isEmpty else { continue }
            let rule = await ruleRegistry.bestRule(for: identity)
            let ruleScore = rule.evidence(for: file, identity: identity).reduce(0) { $0 + $1.weight }
            let assessment = ConfidenceEngine.assess(evidence, ruleScore: ruleScore, identity: identity)
            if assessment.tier >= .possible { return true }
        }
        
        return false
    }

    private func stripTeamIDPrefix(from string: String) -> String {
        Self.stripTeamIDPrefix(from: string)
    }

    public static func displayName(fromDotSeparated base: String) -> String {
        let rawParts = base.split(separator: ".").map(String.init)
        guard rawParts.count >= 2 else { return base }

        // Versioned tool/app plists like "python3.8", "python3.12", "app.2.0"
        if rawParts.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return base
        }

        var parts = rawParts
        let technicalTails: Set<String> = ["lssharedfilelist"]
        while parts.count > 2, let last = parts.last, technicalTails.contains(last.lowercased()) {
            parts.removeLast()
        }

        let last = parts.last ?? base
        if parts.count >= 2, !last.isEmpty, last.allSatisfy(\.isNumber) {
            let prev = parts[parts.count - 2]
            let tldStopwords: Set<String> = ["com", "org", "net", "io", "app", "dev", "co", "uk", "de", "ru"]
            if !tldStopwords.contains(prev.lowercased()) {
                if prev.last?.isNumber == true {
                    return "\(prev).\(last)"
                }
                return "\(formatSegment(prev)) \(last)"
            }
            return base
        }

        return formatSegment(last)
    }

    private static func formatSegment(_ segment: String) -> String {
        guard !segment.isEmpty else { return segment }
        if segment.contains(where: \.isUppercase) {
            return segment
        }
        return segment.prefix(1).uppercased() + segment.dropFirst()
    }

    private static let residualFileExtensions: Set<String> = [
        "plist", "savedstate", "sfl", "sfl2", "sfl3", "sfl4",
        "binarycookies", "log", "json", "yaml", "yml", "xml", "conf"
    ]

    private static func strippingResidualExtension(from filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, residualFileExtensions.contains(ext) else {
            return filename
        }
        return (filename as NSString).deletingPathExtension
    }

    public static func extractBundleIDAndName(from file: URL) -> (bundleID: String?, name: String) {
        var filename = file.lastPathComponent
        let path = file.path

        // Clean team ID prefix e.g. TC3Q7MAJXF.com.adguard.mac -> com.adguard.mac
        filename = stripTeamIDPrefix(from: filename)
        filename = filename.replacingOccurrences(of: "group.", with: "")
                           .replacingOccurrences(of: "groups.", with: "")

        // Check if plist has embedded bundle identifier
        if filename.lowercased().hasSuffix(".plist") {
            let base = (filename as NSString).deletingPathExtension
            if base.contains(".") && !base.hasPrefix(".") {
                return (base, displayName(fromDotSeparated: base))
            }
        }

        // Check Containers & Group Containers
        if path.contains("/Containers/") || path.contains("/Group Containers/") {
            let clean = strippingResidualExtension(from: filename)
            if clean.contains(".") {
                return (clean, displayName(fromDotSeparated: clean))
            }
        }

        // Check Saved Application State
        if filename.lowercased().hasSuffix(".savedstate") {
            let base = (filename as NSString).deletingPathExtension
            if base.contains(".") {
                return (base, displayName(fromDotSeparated: base))
            }
        }

        // Check reverse DNS pattern in folder/file names (com.something.app or org.something.app)
        if filename.contains(".") && !filename.hasPrefix(".") {
            let prefixes = ["com.", "org.", "net.", "io.", "app.", "dev.", "co.", "uk.", "de.", "ru."]
            if prefixes.contains(where: { filename.lowercased().hasPrefix($0) }) {
                let clean = strippingResidualExtension(from: filename)
                return (clean, displayName(fromDotSeparated: clean))
            }
        }

        return (nil, filename)
    }

    private func collectOrphanEvidence(
        for file: URL,
        bundleID: String?,
        name: String,
        probe: EvidenceProbe
    ) async -> (evidence: Set<Evidence>, score: Int, tier: ConfidenceTier) {
        var evidence = Set<Evidence>()
        let path = file.path

        // Only give bundleIDExact if we have a real structured reverse-DNS bundleID (contains dots and valid format)
        if let bid = bundleID, bid.contains("."), bid.components(separatedBy: ".").count >= 3 {
            evidence.insert(.bundleIDExact)
        }

        if path.contains("/Containers/") {
            evidence.insert(.container)
        }
        if path.contains("/Group Containers/") {
            evidence.insert(.appGroup)
        }
        if path.contains("/LaunchAgents/") {
            evidence.insert(.launchAgent)
        }
        if path.contains("/LaunchDaemons/") {
            evidence.insert(.launchDaemon)
        }
        if file.pathExtension.lowercased() == "plist" || path.contains("/Preferences/") {
            evidence.insert(.plistContent)
        }

        // Synthetic AppIdentity for probe analysis
        guard let validBundleID = bundleID, validBundleID.contains(".") else {
            return (evidence, 0, .ignore)
        }

        let syntheticIdentity = AppIdentity(
            bundleID: validBundleID,
            appName: name,
            bundleName: name,
            bundleVersion: nil,
            executableName: name,
            teamID: nil,
            signingAuthority: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            isAppStore: false,
            isSandboxed: path.contains("/Containers/"),
            isAdHocSigned: false,
            vendorNames: [],
            helperNames: [],
            frameworkNames: [],
            xpcServiceNames: [],
            plugInNames: [],
            isElectron: path.contains("Electron"),
            isJetBrains: path.contains("JetBrains"),
            isFlutter: path.contains("Flutter"),
            isJava: false,
            isQt: false,
            isDocker: false
        )

        let probeEvidence = await probe.probe(url: file, identity: syntheticIdentity)
        evidence.formUnion(probeEvidence)

        let rule = await ruleRegistry.bestRule(for: syntheticIdentity)
        let ruleScore = rule.evidence(for: file, identity: syntheticIdentity).reduce(0) { $0 + $1.weight }

        let assessment = ConfidenceEngine.assess(evidence, ruleScore: ruleScore, identity: syntheticIdentity)
        var tier = assessment.tier
        let lowerFilename = file.lastPathComponent.lowercased()
        if lowerFilename.hasPrefix("homebrew.mxcl.") || lowerFilename.hasPrefix("homebrew.cask.") {
            // Homebrew formula services must never be marked Guaranteed (they may belong to CLI formulae).
            if Self.extractLaunchdExecutablePaths(from: file).isEmpty {
                tier = min(tier, .possible)
            } else {
                tier = min(tier, .veryLikely)
            }
        }
        return (evidence, assessment.score, tier)
    }
    
    private func collectAllScanTargets() async -> Set<URL> {
        let home = fileSystemContext.homePath
        
        // Same as CandidateCollector basePaths and XDG
        let basePaths = [
            NormalizedPath.joinHome(home, "Library/Application Support"),
            NormalizedPath.joinHome(home, "Library/Caches"),
            NormalizedPath.joinHome(home, "Library/Containers"),
            NormalizedPath.joinHome(home, "Library/Group Containers"),
            NormalizedPath.joinHome(home, "Library/Preferences"),
            NormalizedPath.joinHome(home, "Library/Logs"),
            NormalizedPath.joinHome(home, "Library/Saved Application State"),
            NormalizedPath.joinHome(home, "Library/Application Scripts"),
            NormalizedPath.joinHome(home, "Library/Screen Savers"),
            NormalizedPath.joinHome(home, "Library/Services"),
            NormalizedPath.joinHome(home, "Library/Frameworks"),
            NormalizedPath.joinHome(home, "Library/PreferencePanes"),
            NormalizedPath.joinHome(home, "Library/LaunchAgents"),
            NormalizedPath.joinHome(home, "Library/HTTPStorages"),
            NormalizedPath.joinHome(home, "Library/WebKit"),
            NormalizedPath.joinHome(home, "Library/Preferences/ByHost"),
            NormalizedPath.joinHome(home, "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"),
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Application Support",
            "/Library/Caches",
            "/Library/Logs",
            "/Library/Preferences",
            "/Library/PrivilegedHelperTools",
            "/Library/Frameworks",
            "/Library/Screen Savers",
            "/Library/Services",
        ]
        
        var targets = Set<URL>()
        autoreleasepool {
            for base in basePaths {
                let url = NormalizedPath.url(base, isDirectory: true)
                guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles) else { continue }
                for content in contents {
                    let isSymlink = (try? content.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                    targets.insert(NormalizedPath.canonicalize(isSymlink ? content.resolvingSymlinksInPath() : content))
                }
            }
            
            for relative in [".config", ".cache", ".local/share"] {
                let xdgPath = NormalizedPath.joinHome(home, relative)
                let url = NormalizedPath.url(xdgPath, isDirectory: true)
                guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles) else { continue }
                for content in contents {
                    let isSymlink = (try? content.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                    targets.insert(NormalizedPath.canonicalize(isSymlink ? content.resolvingSymlinksInPath() : content))
                }
            }

            // Home dot-folders (~/.cursor, ~/.anydesk, ~/.antigravity)
            let homeURL = NormalizedPath.url(home, isDirectory: true)
            if let homeContents = try? fileManager.contentsOfDirectory(at: homeURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) {
                for item in homeContents where item.lastPathComponent.hasPrefix(".") {
                    let isSymlink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
                    targets.insert(NormalizedPath.canonicalize(isSymlink ? item.resolvingSymlinksInPath() : item))
                }
            }
        }
        
        return targets
    }
}
