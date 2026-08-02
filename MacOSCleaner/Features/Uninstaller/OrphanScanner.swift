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

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        bundleID: String?,
        sizeBytes: Int64,
        category: String,
        modificationDate: Date? = nil
    ) {
        self.id = id
        self.url = NormalizedPath.canonicalize(url)
        self.name = name
        self.bundleID = bundleID
        self.sizeBytes = sizeBytes
        self.category = category
        self.modificationDate = modificationDate
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(NormalizedPath.key(url))
    }

    public static func == (lhs: OrphanItem, rhs: OrphanItem) -> Bool {
        NormalizedPath.key(lhs.url) == NormalizedPath.key(rhs.url)
    }
}

public actor OrphanScanner {
    private let safetyManager: SafetyManager
    private let commandRunner: CommandRunner
    private let fileSystemContext: FileSystemContext
    private let codesignCache: CodesignCache
    private let plistCache: PlistContentCache
    private let ruleRegistry: ApplicationRuleRegistry
    private let fileManager = FileManager.default

    public init(
        safetyManager: SafetyManager,
        commandRunner: CommandRunner = CommandRunner(),
        fileSystemContext: FileSystemContext = .production,
        codesignCache: CodesignCache = CodesignCache(),
        plistCache: PlistContentCache = PlistContentCache(),
        ruleRegistry: ApplicationRuleRegistry = .shared
    ) {
        self.safetyManager = safetyManager
        self.commandRunner = commandRunner
        self.fileSystemContext = fileSystemContext
        self.codesignCache = codesignCache
        self.plistCache = plistCache
        self.ruleRegistry = ruleRegistry
    }

    public func scanOrphans(progress: ((String) -> Void)? = nil) async throws -> [OrphanItem] {
        try Task.checkCancellation()
        progress?("Discovering installed applications...")
        
        // 1. Discover installed apps
        let discovery = AppDiscovery()
        let installedURLs = await discovery.findAll()
        var identities: [AppIdentity] = []
        for url in installedURLs {
            let identity = await AppIdentity.resolve(from: url, commandRunner: commandRunner)
            identities.append(identity)
        }
        
        try Task.checkCancellation()
        progress?("Scanning target directories...")
        
        // 2. Collect ALL files from scan directories
        let allFiles = await collectAllScanTargets()
        
        progress?("Analyzing \(allFiles.count) potential orphans...")
        let probe = EvidenceProbe(
            commandRunner: commandRunner,
            codesignCache: codesignCache,
            plistCache: plistCache
        )
        
        var orphans: [OrphanItem] = []
        var processed = 0
        let total = allFiles.count
        
        for file in allFiles {
            try Task.checkCancellation()
            processed += 1
            if processed % 100 == 0 {
                progress?("Analyzing \(processed)/\(total)...")
            }
            
            // Basic safety & size filters
            guard (try? safetyManager.validate(url: file)) != nil else { continue }
            
            // Skip Apple system items immediately
            let filename = file.lastPathComponent
            if filename.hasPrefix("com.apple.") || filename.hasPrefix("com.mac.") {
                continue
            }
            
            let isOwned = await checkOwnership(
                file: file,
                identities: identities,
                probe: probe
            )
            
            if !isOwned {
                let size = fileManager.getDirectorySize(url: file)
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
                else if pathStr.contains("/Developer/") || pathStr.contains("CommandLineTools") { category = "Developer" }
                
                orphans.append(OrphanItem(
                    url: file,
                    name: filename,
                    bundleID: nil, // We could try to extract it from filename if needed, but not critical
                    sizeBytes: size,
                    category: category,
                    modificationDate: modDate
                ))
                Logger.orphanScanner.debug("Found orphan: \(filename, privacy: .public) (\(size) bytes)")
            }
        }
        
        return orphans.sorted { $0.sizeBytes > $1.sizeBytes }
    }
    
    private func checkOwnership(
        file: URL,
        identities: [AppIdentity],
        probe: EvidenceProbe
    ) async -> Bool {
        let filename = file.lastPathComponent.lowercased()
        let path = file.path.lowercased()
        
        // Fast path priority check
        let priorityApps = identities.filter { identity in
            let bid = identity.bundleID.lowercased()
            return filename.contains(bid) || path.contains(bid) || filename.contains(identity.appName.lowercased())
        }
        
        for identity in priorityApps {
            let evidence = await probe.probe(url: file, identity: identity)
            guard !evidence.isEmpty else { continue }
            let rule = await ruleRegistry.bestRule(for: identity)
            let ruleScore = rule.evidence(for: file, identity: identity).reduce(0) { $0 + $1.weight }
            let assessment = ConfidenceEngine.assess(evidence, ruleScore: ruleScore, identity: identity)
            if assessment.tier >= .veryLikely { return true }
        }
        
        if !priorityApps.isEmpty { return false }
        
        // Full check for unresolved files
        for identity in identities {
            let evidence = await probe.probe(url: file, identity: identity)
            guard !evidence.isEmpty else { continue }
            let rule = await ruleRegistry.bestRule(for: identity)
            let ruleScore = rule.evidence(for: file, identity: identity).reduce(0) { $0 + $1.weight }
            let assessment = ConfidenceEngine.assess(evidence, ruleScore: ruleScore, identity: identity)
            if assessment.tier >= .veryLikely { return true }
        }
        return false
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
        for base in basePaths {
            let url = NormalizedPath.url(base, isDirectory: true)
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            for content in contents {
                targets.insert(content.resolvingSymlinksInPath())
            }
        }
        
        for relative in [".config", ".cache", ".local/share"] {
            let xdgPath = NormalizedPath.joinHome(home, relative)
            let url = NormalizedPath.url(xdgPath, isDirectory: true)
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { continue }
            for content in contents {
                targets.insert(content.resolvingSymlinksInPath())
            }
        }

        // Home dot-folders (~/.cursor, ~/.anydesk, ~/.antigravity)
        let homeURL = NormalizedPath.url(home, isDirectory: true)
        if let homeContents = try? fileManager.contentsOfDirectory(at: homeURL, includingPropertiesForKeys: nil, options: []) {
            for item in homeContents where item.lastPathComponent.hasPrefix(".") {
                targets.insert(item.resolvingSymlinksInPath())
            }
        }
        
        return targets
    }
}
