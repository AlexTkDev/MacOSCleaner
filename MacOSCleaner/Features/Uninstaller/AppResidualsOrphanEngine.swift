import Foundation
import OSLog

private extension Logger {
    static let orphanEngine = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "AppResidualsOrphanEngine")
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

public actor AppResidualsOrphanEngine {
    // FileManager is not Sendable — use .default locally, never store or pass across actor boundaries.
    private let safetyManager: SafetyManager
    private let trashManager: TrashManager
    private let commandRunner: CommandRunner
    private let fileSystemContext: FileSystemContext

    private struct InstalledAppRecord: Sendable {
        let url: URL
        let bundleID: String
        let appName: String
        let bundleName: String?
        let executableName: String
        let teamID: String?
        let appGroups: Set<String>
    }

    private struct IndexedEntry: Sendable {
        let url: URL
        let category: String
    }

    public init(
        safetyManager: SafetyManager? = nil,
        trashManager: TrashManager = TrashManager(),
        commandRunner: CommandRunner = CommandRunner(),
        fileSystemContext: FileSystemContext = .production
    ) {
        self.fileSystemContext = fileSystemContext
        self.safetyManager = safetyManager ?? SafetyManager(
            homeDirectory: fileSystemContext.homePath,
            fileSystemContext: fileSystemContext
        )
        self.trashManager = trashManager
        self.commandRunner = commandRunner
    }

    // MARK: - Scan Installed Applications

    /// Collects bundle IDs, app names, and executable names for all currently installed applications.
    public func collectInstalledAppIdentifiers() async throws -> Set<String> {
        let records = try await collectInstalledAppRecords()
        var collected = Set<String>()
        for record in records {
            collected.formUnion(identifiers(for: record))
        }
        collected.formUnion(try await collectReceiptPackageIdentifiers(matching: Set(records.map(\.bundleID))))
        return collected
    }

    // MARK: - Bundle ID Extraction

    /// Dynamically extracts `bundle_id` or app identifier from directory name or metadata files.
    public func extractBundleID(from directoryURL: URL) -> String? {
        let folderName = directoryURL.lastPathComponent

        // 1. Direct bundle ID format: com.vendor.app or group.com.vendor.app
        if isBundleIDPattern(folderName) {
            return cleanGroupPrefix(folderName)
        }

        // 2. Container metadata: Container.plist
        let containerPlistURL = directoryURL.appendingPathComponent("Container.plist")
        if FileManager.default.fileExists(atPath: containerPlistURL.path),
           let data = try? Data(contentsOf: containerPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let id = plist["MCMMetadataIdentifier"] as? String {
            return cleanGroupPrefix(id)
        }

        // 3. Nested Info.plist if folder represents a bundle or container root
        let infoPlistURL = directoryURL.appendingPathComponent("Contents/Info.plist")
        if FileManager.default.fileExists(atPath: infoPlistURL.path),
           let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let id = plist["CFBundleIdentifier"] as? String {
            return cleanGroupPrefix(id)
        }

        // 4. Preferences plist (e.g. com.vendor.app.plist)
        if folderName.hasSuffix(".plist") {
            let nameWithoutExt = (folderName as NSString).deletingPathExtension
            if isBundleIDPattern(nameWithoutExt) {
                return cleanGroupPrefix(nameWithoutExt)
            }
        }

        return nil
    }

    // MARK: - Main Scan Engine

    /// Dynamically scans key macOS system directories for application residual files (Orphans) left by uninstalled apps.
    public func scanOrphans(progress: ((String) -> Void)? = nil) async throws -> [OrphanItem] {
        try Task.checkCancellation()
        let installedApps = try await collectInstalledAppRecords()
        let receiptPackageIDs = try await collectReceiptPackageIdentifiers(matching: Set(installedApps.map(\.bundleID)))
        let indexedEntries = try await indexTargetDirectories(progress: progress)

        var orphans: [OrphanItem] = []

        for entry in indexedEntries {
            try Task.checkCancellation()

            if isAppleSystemOrFrameworkEntry(entry.url.lastPathComponent) {
                continue
            }

            if isHeavyContainer(entry.url.lastPathComponent) {
                continue
            }

            guard (try? safetyManager.validate(url: entry.url)) != nil else {
                continue
            }

            let assessment = try await assessOwnership(
                for: entry,
                installedApps: installedApps,
                receiptPackageIDs: receiptPackageIDs
            )
            guard !assessment.isInstalled else {
                continue
            }
            guard assessment.clueKinds.count >= 2 else {
                continue
            }

            let size = FileManager.default.getDirectorySize(url: entry.url)
            guard size > 50 * 1024 else {
                continue
            }

            let modDate = (try? FileManager.default.attributesOfItem(atPath: entry.url.path)[.modificationDate] as? Date)
            orphans.append(OrphanItem(
                url: entry.url,
                name: entry.url.lastPathComponent,
                bundleID: extractBundleID(from: entry.url),
                sizeBytes: size,
                category: entry.category,
                modificationDate: modDate
            ))
            Logger.orphanEngine.debug("Found orphan: \(entry.url.lastPathComponent, privacy: .public) (\(size, privacy: .public) bytes) in \(entry.category, privacy: .public)")
        }

        var uniqueByPath: [String: OrphanItem] = [:]
        for orphan in orphans {
            uniqueByPath[NormalizedPath.key(orphan.url)] = orphan
        }
        return Array(uniqueByPath.values).sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Removal (Trash or Permanent based on AppSettings)

    /// Safely removes specified orphan items (moves to Trash, or deletes directly if `bypassTrash` is enabled).
    public func trashOrphans(_ items: [OrphanItem], bypassTrash: Bool? = nil) async throws -> Int64 {
        let shouldBypass = bypassTrash ?? UserDefaults.standard.bool(forKey: "settings_bypassTrashOnUninstall")
        var totalFreed: Int64 = 0

        for item in items {
            try Task.checkCancellation()
            do {
                try safetyManager.validate(url: item.url, policy: .uninstall)
                if shouldBypass {
                    try Task.checkCancellation()
                    try FileManager.default.removeItem(at: item.url)
                    totalFreed += item.sizeBytes
                    Logger.orphanEngine.info("Permanently deleted orphan item: \(item.url.path, privacy: .public)")
                } else {
                    try Task.checkCancellation()
                    _ = try await trashManager.trashItem(at: item.url, policy: .uninstall)
                    totalFreed += item.sizeBytes
                    Logger.orphanEngine.info("Trashed orphan item: \(item.url.path, privacy: .public)")
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                Logger.orphanEngine.error("Failed to remove orphan item \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return totalFreed
    }

    // MARK: - Helper Methods

    private func isBundleIDPattern(_ text: String) -> Bool {
        let parts = text.components(separatedBy: ".")
        return parts.count >= 3 && !text.contains(" ")
    }

    private func cleanGroupPrefix(_ id: String) -> String {
        if id.hasPrefix("group.") {
            return String(id.dropFirst(6))
        }
        return id
    }

    private func isAppleSystemOrFrameworkEntry(_ entry: String) -> Bool {
        let lower = entry.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") || lower.hasPrefix("system.") {
            return true
        }

        let appleKeywords = [
            "caches", "logs", "preferences", "byhost", "metadata", "suggestions",
            "cloudkit", "identityservices", "messages", "geoservices",
            "mobile documents", "relocated items", "previously relocated items",
            "animoji", "passkit", "gamekit", "gamecenter", "familycircle", "familycircled",
            "knowledge", "spotlight", "music", "contactsd", "homeenergyd",
            "networkserviceproxy", "mediaanalysisd", "duetexpertcenter",
            "coresuggestions", "medialibrary", "imcore", "telephonyutilities",
            "usereventagent", "applemusicservices", "pencilkit", "screentime",
            "homekit", "healthkit", "storekit", "corelocation", "coremotion",
            "corenfc", "carplay", "classkit", "shazamkit", "safariservices",
            "linkpresentation", "intents", "assistant", "siri",
            "contextstoreagent", "mobilemeaccounts", "loginwindow",
            "diagnostics_agent", "mbuseragent", "is.workflow"
        ]

        return appleKeywords.contains(where: { lower.contains($0) })
    }

    private func isHeavyContainer(_ entry: String) -> Bool {
        let lower = entry.lowercased()
        return lower.contains("com.docker.docker") || lower.contains("com.orbstack") || lower.contains("utm")
    }

    private func collectInstalledAppRecords() async throws -> [InstalledAppRecord] {
        let discovery = AppDiscovery(commandRunner: commandRunner)
        let appURLs = await discovery.findAll()
        var records: [InstalledAppRecord] = []
        var seenPaths = Set<String>()

        for appURL in appURLs {
            try Task.checkCancellation()
            let standardized = NormalizedPath.canonicalize(appURL)
            guard seenPaths.insert(NormalizedPath.key(standardized)).inserted else { continue }

            let identity = await AppIdentity.resolve(from: standardized, commandRunner: commandRunner)
            records.append(InstalledAppRecord(
                url: standardized,
                bundleID: identity.bundleID.lowercased(),
                appName: identity.appName.lowercased(),
                bundleName: identity.bundleName?.lowercased(),
                executableName: identity.executableName.lowercased(),
                teamID: identity.teamID?.lowercased(),
                appGroups: Set(identity.appGroups.map { $0.lowercased() })
            ))
        }

        return records
    }

    private func indexTargetDirectories(progress: ((String) -> Void)? = nil) async throws -> [IndexedEntry] {
        let home = fileSystemContext.homePath
        let targetDirectories: [(path: String, category: String)] = [
            ("\(home)/Library/Containers", "Containers"),
            ("\(home)/Library/Application Support", "Application Support"),
            ("\(home)/Library/Group Containers", "Group Containers"),
            ("\(home)/Library/Caches", "Caches"),
            ("\(home)/Library/Preferences", "Preferences"),
            ("\(home)/Library/Saved Application State", "Saved App State"),
            ("\(home)/Library/HTTPStorages", "HTTPStorages"),
            ("\(home)/Library/Cookies", "Cookies"),
            ("\(home)/Library/WebKit", "WebKit"),
            ("\(home)/Library/Logs", "Logs"),
            ("\(home)/Library/Application Scripts", "Application Scripts"),
            ("\(home)/Library/Internet Plug-Ins", "Internet Plug-Ins"),
        ]

        var index: [IndexedEntry] = []
        for (scanDir, category) in targetDirectories {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: scanDir) else { continue }
            progress?("Scanning \(category)...")

            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: scanDir) else { continue }
            for entry in entries {
                try Task.checkCancellation()
                index.append(IndexedEntry(
                    url: NormalizedPath.url(NormalizedPath.join(scanDir, entry)),
                    category: category
                ))
            }
        }

        return index
    }

    private func collectReceiptPackageIdentifiers(matching bundleIDs: Set<String>) async throws -> Set<String> {
        guard !bundleIDs.isEmpty else { return [] }

        var packageIDs = Set<String>()
        let result: CommandResult
        do {
            result = try await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--pkgs"])
        } catch let error as CancellationError {
            throw error
        } catch {
            return packageIDs
        }
        guard result.exitCode == 0 else { return packageIDs }

        for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
            let lower = line.lowercased()
            if bundleIDs.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") }) {
                packageIDs.insert(lower)
            }
        }

        return packageIDs
    }

    private func identifiers(for record: InstalledAppRecord) -> Set<String> {
        var identifiers = Set<String>()
        identifiers.insert(record.bundleID)
        identifiers.insert(record.appName)
        identifiers.insert(record.executableName)
        if let bundleName = record.bundleName, !bundleName.isEmpty {
            identifiers.insert(bundleName)
        }
        if let teamID = record.teamID, !teamID.isEmpty {
            identifiers.insert(teamID)
        }
        identifiers.formUnion(record.appGroups)
        identifiers.insert(record.url.standardizedFileURL.path.lowercased())
        identifiers.insert(record.url.deletingPathExtension().lastPathComponent.lowercased())
        return Set(identifiers.filter { !$0.isEmpty })
    }

    private func assessOwnership(
        for entry: IndexedEntry,
        installedApps: [InstalledAppRecord],
        receiptPackageIDs: Set<String>
    ) async throws -> (isInstalled: Bool, clueKinds: Set<String>) {
        try Task.checkCancellation()

        let entryURL = entry.url.standardizedFileURL
        let lowerName = entryURL.lastPathComponent.lowercased()
        let lowerPath = entryURL.path.lowercased()
        let extractedBundleID = extractBundleID(from: entryURL)?.lowercased()
        var clueKinds: Set<String> = []

        if extractedBundleID != nil {
            clueKinds.insert("bundleID")
        }
        if lowerName.hasPrefix("group.") {
            clueKinds.insert("appGroup")
        }
        if lowerPath.contains("/containers/") {
            clueKinds.insert("container")
        }
        if let teamID = try await extractTeamID(from: entryURL) {
            clueKinds.insert("teamID")
            if lowerName.hasPrefix(teamID.lowercased() + ".") {
                clueKinds.insert("appGroup")
            }
        }

        if receiptPackageIDs.contains(where: { receipt in
            lowerName == receipt || lowerName.hasPrefix(receipt + ".") || extractedBundleID == receipt
        }) {
            clueKinds.insert("receipt")
        }

        for app in installedApps {
            try Task.checkCancellation()

            let appPath = app.url.standardizedFileURL.path.lowercased()
            if lowerPath == appPath || lowerPath.hasPrefix(appPath + "/") {
                return (true, [])
            }

            if let extractedBundleID,
               (extractedBundleID == app.bundleID || extractedBundleID.hasPrefix(app.bundleID + ".")) {
                clueKinds.insert("bundleID")
            }

            if lowerName == app.bundleID || lowerName.hasPrefix(app.bundleID + ".") {
                clueKinds.insert("bundleID")
            }

            if lowerName == app.appName
                || lowerName.hasPrefix(app.appName + " ")
                || lowerName.hasPrefix(app.appName + ".")
                || lowerName.hasPrefix(app.appName + "-") {
                clueKinds.insert("appName")
            }

            if let bundleName = app.bundleName, !bundleName.isEmpty,
               (lowerName == bundleName
                || lowerName.hasPrefix(bundleName + " ")
                || lowerName.hasPrefix(bundleName + ".")
                || lowerName.hasPrefix(bundleName + "-")) {
                clueKinds.insert("bundleName")
            }

            if lowerName == app.executableName {
                clueKinds.insert("executable")
            }

            if let teamID = app.teamID, !teamID.isEmpty,
               entryURL.lastPathComponent.hasPrefix(teamID + ".") {
                clueKinds.insert("teamID")
            }

            if app.appGroups.contains(lowerName) {
                clueKinds.insert("appGroup")
            }

            if entryURL.path.contains("/Group Containers/") {
                if let teamID = app.teamID, !teamID.isEmpty,
                   entryURL.lastPathComponent.hasPrefix(teamID + ".") {
                    clueKinds.insert("teamID")
                }
                if app.appGroups.contains(lowerName) {
                    clueKinds.insert("appGroup")
                }
            }
        }

        return (false, clueKinds)
    }

    private func extractTeamID(from url: URL) async throws -> String? {
        let result: CommandResult
        do {
            result = try await commandRunner.run(
                command: "/usr/bin/codesign",
                arguments: ["-dv", "--verbose=4", url.path]
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            return nil
        }
        let output = result.stderr
        guard let range = output.range(of: "TeamIdentifier=") else { return nil }
        let start = range.upperBound
        let end = output[start...].firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? output.endIndex
        return String(output[start..<end])
    }

    private func isEntryInstalled(entry: String, extractedID: String?, installedApps: Set<String>) -> Bool {
        let lowerEntry = entry.lowercased()

        // 1. Exact match on folder name or extracted bundle ID
        if installedApps.contains(lowerEntry) { return true }
        if let id = extractedID?.lowercased() {
            if installedApps.contains(id) { return true }
            // Same family: com.foo.bar ↔ com.foo.bar.helper
            if installedApps.contains(where: { $0 == id || $0.hasPrefix(id + ".") || id.hasPrefix($0 + ".") }) {
                return true
            }
            // Reverse-DNS orphans: no fuzzy/substring matching (avoids "com"/"test" false positives)
            if isBundleIDPattern(id) || isBundleIDPattern(lowerEntry) {
                return false
            }
        } else if isBundleIDPattern(lowerEntry) {
            if installedApps.contains(where: { $0 == lowerEntry || $0.hasPrefix(lowerEntry + ".") || lowerEntry.hasPrefix($0 + ".") }) {
                return true
            }
            return false
        }

        // 2. Fuzzy match for human-named folders only (Steam, Adobe, …)
        for app in installedApps where app.count >= 5 {
            if lowerEntry.contains(app) || app.contains(lowerEntry) { return true }
        }

        // 3. Known common vendors
        if (lowerEntry.contains("microsoft") || lowerEntry.contains("office")) && installedApps.contains(where: { $0.contains("microsoft") || $0.contains("office") }) {
            return true
        }
        if lowerEntry.contains("adobe") && installedApps.contains(where: { $0.contains("adobe") }) {
            return true
        }
        if lowerEntry.contains("google") && installedApps.contains(where: { $0.contains("google") }) {
            return true
        }

        return false
    }
}
