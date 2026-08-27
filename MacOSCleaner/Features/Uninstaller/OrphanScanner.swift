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
            guard (try? safetyManager.validate(url: file, policy: .uninstall)) != nil else { continue }
            
            // Skip Apple system items, system daemons, and developer toolchain containers
            if isSystemOrProtected(file: file) {
                continue
            }
            
            let isOwned = await checkOwnership(
                file: file,
                identities: identities,
                probe: probe
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
                else if pathStr.contains("/Developer/") || pathStr.contains("CommandLineTools") { category = "Developer" }
                
                let extracted = extractBundleIDAndName(from: file)
                
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

    private func isSystemOrProtected(file: URL) -> Bool {
        let rawFilename = file.lastPathComponent.lowercased()
        let filename = stripTeamIDPrefix(from: rawFilename)
            .replacingOccurrences(of: "group.", with: "")
            .replacingOccurrences(of: "groups.", with: "")

        // Apple system containers, groups, daemons and system tools
        if rawFilename.contains("com.apple.") ||
           rawFilename.contains(".apple.") ||
           rawFilename.contains("group.com.apple") ||
           rawFilename.contains("groups.com.apple") ||
           filename.hasPrefix("com.apple.") ||
           filename.hasPrefix("com.mac.") ||
           filename.hasPrefix("is.workflow.") ||
           filename.hasPrefix("org.swift.") ||
           filename.hasPrefix("org.llvm.") ||
           filename.hasPrefix("org.gnu.") ||
           filename.hasPrefix("org.cups.") ||
           filename.hasPrefix("org.sparkle-project.") ||
           filename.hasPrefix("org.openldap.") ||
           filename.hasPrefix("org.apache.") {
            return true
        }

        return false
    }

    private func stripTeamIDPrefix(from string: String) -> String {
        let pattern = #"^[A-Z0-9]{10}\.(?:groups?\.)?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: string.utf16.count)
            return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
        }
        return string
    }
    
    private func checkOwnership(
        file: URL,
        identities: [AppIdentity],
        probe: EvidenceProbe
    ) async -> Bool {
        let rawFilename = file.lastPathComponent.lowercased()
        let filename = stripTeamIDPrefix(from: rawFilename)
            .replacingOccurrences(of: "group.", with: "")
            .replacingOccurrences(of: "groups.", with: "")
        let path = file.path.lowercased()
        let cleanName = (filename as NSString).deletingPathExtension.lowercased()

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
                if cleanName.count >= 4 && (appName.hasPrefix(cleanName + " ") || appName.hasSuffix(" " + cleanName)) {
                    return true
                }
                let appTokens = appName.components(separatedBy: CharacterSet(charactersIn: " -_.")).filter { $0.count >= 4 }
                for token in appTokens {
                    if cleanName.contains(token) || filename.contains(token) {
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
                let exists = await commandRunner.commandExists(toolName)
                if exists {
                    return true
                }
            }
        }

        if cleanName.contains("java") || cleanName.contains("openjdk") {
            if await commandRunner.commandExists("java") {
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

    private func extractBundleIDAndName(from file: URL) -> (bundleID: String?, name: String) {
        var filename = file.lastPathComponent
        let path = file.path

        // Clean team ID prefix e.g. TC3Q7MAJXF.com.adguard.mac -> com.adguard.mac
        filename = stripTeamIDPrefix(from: filename)
        filename = filename.replacingOccurrences(of: "group.", with: "")
                           .replacingOccurrences(of: "groups.", with: "")

        // Check if plist has embedded bundle identifier
        if filename.hasSuffix(".plist") {
            let base = (filename as NSString).deletingPathExtension
            if base.contains(".") && !base.hasPrefix(".") {
                let parts = base.components(separatedBy: ".")
                let lastPart = parts.last?.capitalized ?? base
                return (base, lastPart)
            }
        }

        // Check Containers & Group Containers
        if path.contains("/Containers/") || path.contains("/Group Containers/") {
            let clean = (filename as NSString).deletingPathExtension
            if clean.contains(".") {
                let parts = clean.components(separatedBy: ".")
                let lastPart = parts.last?.capitalized ?? clean
                return (clean, lastPart)
            }
        }

        // Check Saved Application State
        if filename.hasSuffix(".savedState") {
            let base = (filename as NSString).deletingPathExtension
            if base.contains(".") {
                let parts = base.components(separatedBy: ".")
                let lastPart = parts.last?.capitalized ?? base
                return (base, lastPart)
            }
        }

        // Check reverse DNS pattern in folder/file names (com.something.app or org.something.app)
        if filename.contains(".") && !filename.hasPrefix(".") {
            let prefixes = ["com.", "org.", "net.", "io.", "app.", "dev.", "co.", "uk.", "de.", "ru."]
            if prefixes.contains(where: { filename.lowercased().hasPrefix($0) }) {
                let clean = (filename as NSString).deletingPathExtension
                let parts = clean.components(separatedBy: ".")
                let lastPart = parts.last?.capitalized ?? clean
                return (clean, lastPart)
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
        return (evidence, assessment.score, assessment.tier)
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
