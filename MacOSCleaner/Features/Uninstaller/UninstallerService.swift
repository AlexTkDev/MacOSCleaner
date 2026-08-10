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
    private let identityCache = IdentityCache()
    private let codesignCache = CodesignCache()
    private let plistCache = PlistContentCache()
    private let ruleRegistry: ApplicationRuleRegistry

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
        self.ruleRegistry = ApplicationRuleRegistry.createDefault()
    }

    // MARK: - Types

    public enum DeletionRisk: String, Sendable, CaseIterable {
        case safe
        case normal
        /// Shared updater / suite component — preselected; user can deselect.
        case shared
    }

    public enum ScanState: Equatable, Sendable {
        case queued
        case discovered
        case scanning(progress: Double?)
        case deepScanned
        case failed(String)
    }

    public struct RelatedCleanupComponent: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let title: String
        public let category: CleanupCategory
        public let sizeBytes: Int64
        public let url: URL
        public var isSelected: Bool = false

        public init(title: String, category: CleanupCategory, sizeBytes: Int64, url: URL, isSelected: Bool = false) {
            self.title = title
            self.category = category
            self.sizeBytes = sizeBytes
            self.url = NormalizedPath.url(url)
            self.isSelected = isSelected
        }

        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: RelatedCleanupComponent, rhs: RelatedCleanupComponent) -> Bool {
            lhs.id == rhs.id && lhs.isSelected == rhs.isSelected && lhs.sizeBytes == rhs.sizeBytes
        }
    }

    public struct RelatedFile: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let url: URL
        public var isSelected: Bool = true
        public let size: Int64
        public let deletionRisk: DeletionRisk
        public let evidence: Set<Evidence>
        public let confidence: ConfidenceTier

        public init(url: URL, isSelected: Bool = true, size: Int64 = 0, deletionRisk: DeletionRisk = .normal, evidence: Set<Evidence> = [], confidence: ConfidenceTier = .possible) {
            self.url = NormalizedPath.url(url)
            self.isSelected = isSelected
            self.size = size
            self.deletionRisk = deletionRisk
            self.evidence = evidence
            self.confidence = confidence
        }

        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: RelatedFile, rhs: RelatedFile) -> Bool {
            lhs.id == rhs.id && lhs.isSelected == rhs.isSelected && lhs.size == rhs.size && lhs.confidence == rhs.confidence
        }
    }

    public struct AppInfo: Identifiable, Sendable, Hashable {
        public let id: UUID
        public var url: URL
        public let bundleID: String?
        public let name: String
        public var relatedFiles: [RelatedFile] = []
        public var developerComponents: [RelatedCleanupComponent] = []
        /// Helper / Electron Helper URLs folded into this app (attached after deep scan).
        public var absorbedHelperURLs: [URL] = []
        public var identity: AppIdentity?
        public var scanState: ScanState = .discovered

        public var size: Int64 = 0
        public var version: String = ""
        public var lastUsed: Date? = nil
        public var iconData: Data? = nil
        /// Multiple versions of the same app grouped together.
        public var versions: [AppInfo] = []

        public init(
            id: UUID = UUID(),
            url: URL,
            bundleID: String? = nil,
            name: String,
            relatedFiles: [RelatedFile] = [],
            developerComponents: [RelatedCleanupComponent] = [],
            absorbedHelperURLs: [URL] = [],
            identity: AppIdentity? = nil,
            scanState: ScanState = .discovered,
            size: Int64 = 0,
            version: String = "",
            lastUsed: Date? = nil,
            iconData: Data? = nil,
            versions: [AppInfo] = []
        ) {
            self.id = id
            self.url = url
            self.bundleID = bundleID
            self.name = name
            self.relatedFiles = relatedFiles
            self.developerComponents = developerComponents
            self.absorbedHelperURLs = absorbedHelperURLs
            self.identity = identity
            self.scanState = scanState
            self.size = size
            self.version = version
            self.lastUsed = lastUsed
            self.iconData = iconData
            self.versions = versions
        }

        public var isGrouped: Bool {
            versions.count > 1
        }

        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
            lhs.id == rhs.id &&
            lhs.relatedFiles == rhs.relatedFiles &&
            lhs.developerComponents == rhs.developerComponents &&
            lhs.absorbedHelperURLs == rhs.absorbedHelperURLs &&
            lhs.scanState == rhs.scanState &&
            lhs.size == rhs.size &&
            lhs.versions == rhs.versions
        }

        public var totalSize: Int64 {
            if !versions.isEmpty {
                return versions.reduce(0) { $0 + $1.totalSize }
            }
            let relatedSize = relatedFiles
                .filter(\.isSelected)
                .reduce(0) { $0 + $1.size }
            let devSize = developerComponents.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
            return size + relatedSize + devSize
        }
    }

    // MARK: - Scan All Applications (Discovery only)

    public func scanAllApplications() async throws -> [AppInfo] {
        let discovery = AppDiscovery(commandRunner: commandRunner)
        // Keep distinct bundle URLs separate even when bundle IDs collide.
        let listable = uniqueApplicationURLs(await discovery.findAll())
            .filter { AppDiscovery.isListableApplication($0) }
        // Progress denominator ≈ final sidebar (helpers indexed but not counted).
        let primaryCount = listable.filter { !HelperAppCollapser.isLikelyHelperURL($0) }.count

        await MainActor.run {
            progress.currentStep = 0
            progress.totalSteps = max(primaryCount, 1)
            progress.message = "uninstaller.progress.discovering".localized
            progress.percentage = 0.0
        }

        return try await withThrowingTaskGroup(of: AppInfo?.self) { group in
            for url in listable {
                group.addTask {
                    do {
                        let app = try await self.discoverAndIndex(url)
                        let countsTowardProgress = !HelperAppCollapser.isLikelyHelperURL(url)
                        await MainActor.run {
                            if countsTowardProgress {
                                self.progress.currentStep += 1
                                self.progress.percentage = Double(self.progress.currentStep)
                                    / Double(self.progress.totalSteps)
                            }
                        }
                        return app
                    } catch {
                        Logger.uninstaller.warning(
                            "Skip '\(url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)"
                        )
                        let countsTowardProgress = !HelperAppCollapser.isLikelyHelperURL(url)
                        await MainActor.run {
                            if countsTowardProgress {
                                self.progress.currentStep += 1
                                self.progress.percentage = Double(self.progress.currentStep)
                                    / Double(self.progress.totalSteps)
                            }
                        }
                        return nil
                    }
                }
            }

            var apps: [AppInfo] = []
            for try await app in group {
                if let app = app { apps.append(app) }
            }

            let merged = mergeApps(apps)
            let collapsed = HelperAppCollapser.collapse(merged).apps

            await MainActor.run {
                // Align counter with what the UI actually lists.
                progress.totalSteps = max(collapsed.count, 1)
                progress.currentStep = collapsed.count
                progress.message = "uninstaller.progress.complete".localized
                progress.percentage = 1.0
            }

            return collapsed.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    /// Keep one entry per physical app bundle path.
    private func uniqueApplicationURLs(_ urls: [URL]) -> [URL] {
        NormalizedPath.unique(urls).sorted { $0.path.localizedCompare($1.path) == .orderedAscending }
    }

    private func discoverAndIndex(_ url: URL) async throws -> AppInfo {
        try safetyManager.validate(url: url, policy: .uninstall)

        let identity = await AppIdentity.resolve(from: url, commandRunner: commandRunner)
        await identityCache.set(bundleID: identity.bundleID, identity: identity)

        let size = await getDirectorySize(url: url)
        let iconData = await MainActor.run {
            NSWorkspace.shared.icon(forFile: url.path).tiffRepresentation
        }
        let mdItem = MDItemCreate(nil, url.path as CFString)
        let lastUsed = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date

        return AppInfo(
            url: NormalizedPath.canonicalize(url),
            bundleID: identity.bundleID,
            name: identity.appName,
            relatedFiles: [],
            developerComponents: [],
            identity: identity,
            scanState: .discovered,
            size: size,
            version: version(from: url),
            lastUsed: lastUsed,
            iconData: iconData
        )
    }

    // MARK: - Deep Forensics

    public func deepScan(_ app: AppInfo, mode: ScanMode = .balanced) async throws -> AppInfo {
        if !app.versions.isEmpty {
            var scannedVersions: [AppInfo] = []
            for versionApp in app.versions {
                let scanned = try await deepScanSingle(versionApp, mode: mode)
                scannedVersions.append(scanned)
            }
            scannedVersions.sort { preferredApp($0, $1) == $0 }

            let primary = scannedVersions[0]
            let versionStrings = scannedVersions.compactMap { $0.version.isEmpty ? nil : $0.version }
            let versionSummary = versionStrings.isEmpty ? primary.version : versionStrings.joined(separator: ", ")

            var updated = app
            updated.versions = scannedVersions
            updated.url = primary.url
            updated.version = versionSummary
            updated.lastUsed = scannedVersions.compactMap(\.lastUsed).max()
            updated.iconData = primary.iconData ?? app.iconData
            updated.relatedFiles = aggregateRelatedFiles(from: scannedVersions)
            updated.developerComponents = aggregateDeveloperComponents(from: scannedVersions)
            updated.absorbedHelperURLs = NormalizedPath.unique(scannedVersions.flatMap(\.absorbedHelperURLs))
            updated.scanState = .deepScanned
            return updated
        } else {
            return try await deepScanSingle(app, mode: mode)
        }
    }

    private func deepScanSingle(_ app: AppInfo, mode: ScanMode = .balanced) async throws -> AppInfo {
        let identity: AppIdentity
        if let existing = app.identity {
            identity = existing
        } else {
            identity = await AppIdentity.resolve(from: app.url, commandRunner: commandRunner)
        }

        var updated = app
        updated.identity = identity
        updated.scanState = .scanning(progress: 0.0)

        let graph = EvidenceGraph(identity: identity)

        async let relatedTask: [RelatedFile] = runDeepRelatedFiles(identity: identity, graph: graph, mode: mode)
        async let developerTask: [RelatedCleanupComponent] = DeveloperComponentsDetector.detect(
            appName: identity.appName,
            bundleID: identity.bundleID
        )

        let (related, developer) = await (relatedTask, developerTask)
        // Developer components are SSOT for IDE tooling paths (gradle/android/sdk, …).
        let developerRoots = developer.map { NormalizedPath.key($0.url) }
        var filteredRelated = related.filter { file in
            !Self.overlapsDeveloperRoot(NormalizedPath.key(file.url), roots: developerRoots)
        }
        filteredRelated = await attachAbsorbedHelpers(
            filteredRelated,
            helperURLs: app.absorbedHelperURLs,
            parentBundlePath: NormalizedPath.key(identity.bundleURL)
        )
        updated.relatedFiles = filteredRelated
        updated.developerComponents = developer
        updated.absorbedHelperURLs = app.absorbedHelperURLs
        updated.scanState = .deepScanned

        return updated
    }

    /// Paths that belong to developer-components SSOT must not also appear as related (or locked Shared).
    static func overlapsDeveloperRoot(_ path: String, roots: [String]) -> Bool {
        let pathKey = NormalizedPath.key(NormalizedPath.url(path))
        return roots.contains { root in
            let rootKey = NormalizedPath.key(NormalizedPath.url(root))
            return pathKey == rootKey || pathKey.hasPrefix(rootKey + "/") || rootKey.hasPrefix(pathKey + "/")
        }
    }

    private func attachAbsorbedHelpers(
        _ related: [RelatedFile],
        helperURLs: [URL],
        parentBundlePath: String
    ) async -> [RelatedFile] {
        guard !helperURLs.isEmpty else { return related }
        var existing = Set(related.map { NormalizedPath.key($0.url) })
        var result = related
        for url in helperURLs {
            let standardized = NormalizedPath.canonicalize(url)
            let path = NormalizedPath.key(standardized)
            if path.hasPrefix(parentBundlePath + "/") { continue }
            guard existing.insert(path).inserted else { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let fileSize = await getDirectorySize(url: standardized)
            result.append(RelatedFile(
                url: standardized,
                isSelected: true,
                size: fileSize,
                deletionRisk: .normal,
                evidence: [.bundleIDExact],
                confidence: .guaranteed
            ))
        }
        return dedupAndSort(result.map { ($0, $0.confidence) })
    }

    private func runDeepRelatedFiles(identity: AppIdentity, graph: EvidenceGraph, mode: ScanMode = .balanced) async -> [RelatedFile] {
        let collector = CandidateCollector(commandRunner: commandRunner)
        let collection = await collector.collectDetailed(identity: identity, mode: mode)
        let probe = EvidenceProbe(commandRunner: commandRunner, codesignCache: codesignCache, plistCache: plistCache)

        // Record evidence
        let receiptKeys = Set(collection.receiptPaths.map(NormalizedPath.key))
        let catalogKeys = Set(collection.catalogPaths.map(NormalizedPath.key))
        for url in collection.candidates {
            var evidences = await probe.probe(url: url, identity: identity)
            let pathKey = NormalizedPath.key(url)
            if receiptKeys.contains(pathKey) {
                evidences.insert(.packageReceipt)
            }
            if catalogKeys.contains(pathKey) {
                evidences.insert(.knownCatalog)
            }
            await graph.record(evidences, for: url)

            // Attach via ParentLinker
            let links = ParentLinker.link(url: url, identity: identity)
            for (parent, via) in links {
                await graph.attach(url, to: parent, via: via)
            }
        }

        // Propogate from seeds
        await graph.propagateFromSeeds(maxDepth: 5)

        // Assess confidence, boosted by app-specific rule knowledge (Docker, Office, ...)
        let rule = await ruleRegistry.bestRule(for: identity)
        let nodes = await graph.allNodes()
        var related: [(RelatedFile, ConfidenceTier)] = []

        // Safe mode: only veryLikely and guaranteed; balanced: possible and above
        let minimumTier: ConfidenceTier = mode == .safe ? .veryLikely : .possible

        for node in nodes {
            let ruleScore = rule.evidence(for: node.url, identity: identity).reduce(0) { $0 + $1.weight }
            let assessment = ConfidenceEngine.assess(node.evidence, ruleScore: ruleScore, identity: identity)
            guard assessment.tier >= minimumTier else { continue }
            guard (try? safetyManager.validate(url: node.url, policy: .uninstall)) != nil else { continue }
            guard !Self.isProtectedMailPath(node.url.path) else { continue }
            guard node.url.path != identity.bundleURL.path else { continue }
            guard !identity.bundleURL.path.hasPrefix(node.url.path + "/") else { continue }
            guard !node.url.path.hasPrefix(identity.bundleURL.path + "/") else { continue }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: node.url.path, isDirectory: &isDir) else { continue }

            let fileSize = await getDirectorySize(url: node.url)
            // Browser user data carries logins/sessions — never label it "safe".
            let risk: DeletionRisk = (node.url.path.contains("Preferences") || safetyManager.isBrowserUserDataPath(node.url.path))
                ? .normal : .safe

            let file = RelatedFile(
                url: node.url,
                // possible = review-only; veryLikely+ preselected
                isSelected: assessment.tier >= .veryLikely,
                size: fileSize,
                deletionRisk: risk,
                evidence: assessment.evidence,
                confidence: assessment.tier
            )
            related.append((file, assessment.tier))
        }

        // Dedup by prefix, sort by tier then path
        var result = dedupAndSort(related)

        let sharedSet = Set(collection.sharedPaths.map(NormalizedPath.key))
        let informationalSet = Set(collection.informationalPaths.map(NormalizedPath.key))

        // Demote any leftover that matches shared/user_content (belt-and-suspenders).
        // Android Studio developer tooling paths stay selectable even if catalog marks them shared.
        let unlockSharedForAndroidStudio = identity.bundleID.lowercased().contains("android.studio")
            || identity.appName.lowercased().contains("android studio")
        result = result.map { file in
            let path = NormalizedPath.key(file.url)
            if sharedSet.contains(path) {
                if unlockSharedForAndroidStudio, Self.isAndroidStudioDeveloperPath(path) {
                    return RelatedFile(
                        url: file.url,
                        isSelected: true,
                        size: file.size,
                        deletionRisk: .normal,
                        evidence: file.evidence,
                        confidence: max(file.confidence, .guaranteed)
                    )
                }
                return RelatedFile(
                    url: file.url,
                    isSelected: false,
                    size: file.size,
                    deletionRisk: .shared,
                    evidence: file.evidence,
                    confidence: file.confidence
                )
            }
            if informationalSet.contains(path) {
                return RelatedFile(
                    url: file.url,
                    isSelected: false,
                    size: file.size,
                    deletionRisk: .normal,
                    evidence: file.evidence,
                    confidence: file.confidence
                )
            }
            return file
        }

        // Shared components (Keystone, MAU, …): preselected for Google Chrome; user may deselect.
        let isChrome = identity.bundleID.lowercased() == "com.google.chrome" || identity.appName.lowercased().contains("chrome")
        var existing = Set(result.map { NormalizedPath.key($0.url) })
        for url in collection.sharedPaths {
            let standardized = NormalizedPath.canonicalize(url)
            guard existing.insert(NormalizedPath.key(standardized)).inserted else { continue }
            if unlockSharedForAndroidStudio, Self.isAndroidStudioDeveloperPath(NormalizedPath.key(standardized)) {
                continue // SSOT is developerComponents / unlocked related above
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDir) else { continue }
            let fileSize = await getDirectorySize(url: standardized)
            result.append(RelatedFile(
                url: standardized,
                isSelected: isChrome,
                size: fileSize,
                deletionRisk: .shared,
                evidence: [],
                confidence: .guaranteed
            ))
        }

        // User content roots: shown for review, never preselected.
        for url in collection.informationalPaths {
            let standardized = NormalizedPath.canonicalize(url)
            guard existing.insert(NormalizedPath.key(standardized)).inserted else { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDir) else { continue }
            let fileSize = await getDirectorySize(url: standardized)
            result.append(RelatedFile(
                url: standardized,
                isSelected: false,
                size: fileSize,
                deletionRisk: .normal,
                evidence: [],
                confidence: .guaranteed
            ))
        }

        // Final path-key dedupe after shared/informational append.
        return dedupAndSort(result.map { ($0, $0.confidence) })
    }

    // MARK: - Batch Deep Scan

    public func deepScanAll(apps: [AppInfo]) async -> [AppInfo] {
        await withTaskGroup(of: AppInfo?.self, returning: [AppInfo].self) { group in
            for app in apps {
                group.addTask {
                    try? await self.deepScan(app)
                }
            }
            var results: [AppInfo] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }

    // MARK: - Backward compatibility

    public func scan(appURL: URL) async throws -> AppInfo {
        guard AppDiscovery.isListableApplication(appURL) else {
            throw SafetyError.protectedPath(appURL.path)
        }
        return try await discoverAndIndex(appURL)
    }

    // MARK: - Orphaned App Residuals

    public func scanOrphanedResiduals() async throws -> [OrphanItem] {
        let scanner = OrphanScanner(
            safetyManager: safetyManager,
            commandRunner: commandRunner,
            codesignCache: codesignCache,
            plistCache: plistCache,
            ruleRegistry: ruleRegistry
        )
        return try await scanner.scanOrphans()
    }

    public func removeOrphanedResiduals(_ items: [OrphanItem], bypassTrash: Bool = false) async throws -> Int64 {
        let shouldBypass = bypassTrash
        var freed: Int64 = 0
        for item in items {
            do {
                if shouldBypass {
                    try safetyManager.validate(url: item.url, policy: .uninstall)
                    try FileManager.default.removeItem(at: item.url)
                } else {
                    try await trashManager.trashItem(at: item.url)
                }
                freed += item.sizeBytes
            } catch {
                Logger.uninstaller.error("Failed to remove orphan \(item.url.path): \(error.localizedDescription)")
            }
        }
        return freed
    }

    // MARK: - Uninstall

    public func uninstall(app: AppInfo, bypassTrash: Bool = false, emptyTrashImmediately: Bool = false) async throws {
        if !app.versions.isEmpty {
            for versionApp in app.versions {
                try await uninstall(app: versionApp, bypassTrash: bypassTrash, emptyTrashImmediately: emptyTrashImmediately)
            }
            return
        }

        Logger.uninstaller.info("Uninstalling '\(app.name, privacy: .public)' bypassTrash=\(bypassTrash)")

        let relatedTargets = app.relatedFiles
            .filter(\.isSelected)
            .map(\.url)
        let devTargets = app.developerComponents.filter(\.isSelected).map(\.url)
        let deletionTargets = relatedTargets + devTargets
        let snapshot = UninstallSnapshot(
            appName: app.name,
            bundleID: app.bundleID ?? "unknown",
            appVersion: app.version.isEmpty ? nil : app.version,
            appBundlePath: app.url.path,
            deletedPaths: [app.url.path] + deletionTargets.map(\.path),
            bypassTrash: bypassTrash
        )
        do {
            let store = SnapshotStore(fileManager: .default)
            try await store.save(snapshot: snapshot)
            Logger.uninstaller.info("Saved uninstall snapshot '\(snapshot.id.uuidString, privacy: .public)'")
        } catch {
            Logger.uninstaller.warning("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
        }

        for file in app.relatedFiles where file.isSelected {
            let path = file.url.path
            if (path.contains("LaunchAgents") || path.contains("LaunchDaemons")), path.hasSuffix(".plist") {
                // bootout is the modern reliable unload; fall back to legacy unload
                let domain = path.contains("LaunchDaemons") ? "system" : "gui/\(getuid())"
                let bootout = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["bootout", domain, path])
                if bootout?.exitCode == 0 {
                    Logger.uninstaller.debug("launchctl bootout: \(path, privacy: .public)")
                } else {
                    do {
                        _ = try await commandRunner.run(command: "/bin/launchctl", arguments: ["unload", path])
                        Logger.uninstaller.debug("Unloaded launchctl: \(path, privacy: .public)")
                    } catch {
                        Logger.uninstaller.warning("launchctl unload failed '\(path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        var trashedURLs: [URL] = []
        let allTargets = [app.url] + deletionTargets

        if bypassTrash {
            var privilegedPaths: [String] = []
            for target in allTargets {
                do {
                    try safetyManager.validate(url: target, policy: .uninstall)
                    try fileManager.removeItem(at: target)
                    Logger.uninstaller.debug("Removed: \(target.path, privacy: .public)")
                } catch {
                    if Self.isPermissionError(error) {
                        privilegedPaths.append(target.path)
                    } else if target == app.url {
                        Logger.uninstaller.error("removeItem failed '\(target.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                        throw error
                    } else {
                        Logger.uninstaller.warning("removeItem failed '\(target.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            if !privilegedPaths.isEmpty {
                Logger.uninstaller.info("Executing single privileged removal for \(privilegedPaths.count) item(s)")
                let escaped = privilegedPaths.map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")
                _ = try await PrivilegedTaskRunner.runAsAdmin(command: "/bin/rm -rf \(escaped)")
                Logger.uninstaller.info("Permanently removed via admin privileges: \(privilegedPaths.count) item(s)")
            }
        } else {
            trashedURLs = try await trashManager.trashItems(urls: allTargets, policy: .uninstall)
            Logger.uninstaller.info("Trashed \(trashedURLs.count) item(s) for '\(app.name, privacy: .public)'")
        }

        if let bundleID = app.bundleID {
            do {
                _ = try await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--forget", bundleID])
                Logger.uninstaller.debug("pkgutil --forget \(bundleID, privacy: .public)")
            } catch {
                Logger.uninstaller.warning("pkgutil --forget '\(bundleID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        // Only permanently delete items we just moved into Trash — never empty whole ~/.Trash.
        // Fires for both normal trash path and bypassTrash permission-error fallback.
        if emptyTrashImmediately, !trashedURLs.isEmpty {
            do {
                try await trashManager.requestTrashAccess()
                _ = try await trashManager.permanentlyDelete(urls: trashedURLs)
            } catch {
                Logger.uninstaller.error("permanent delete of trashed items failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        Logger.uninstaller.info("Uninstall complete: '\(app.name, privacy: .public)'")

        // Verification
        if let identity = app.identity {
            let engine = VerificationEngine(
                commandRunner: commandRunner,
                codesignCache: codesignCache,
                plistCache: plistCache
            )
            let report = await engine.verify(identity: identity)
            if report.hasLeftovers {
                Logger.uninstaller.warning("\(report.count, privacy: .public) leftover(s) after uninstall of '\(app.name, privacy: .public)'")
            } else {
                Logger.uninstaller.info("0 leftovers — clean uninstall of '\(app.name, privacy: .public)'")
            }
        }
    }

    // MARK: - Private helpers

    /// NSCocoaErrorDomain 513 = NSFileWriteNoPermissionError (maps to POSIX EPERM/EACCES).
    static func isPermissionError(_ error: Error) -> Bool {
        let code = (error as NSError).code
        return code == NSFileWriteNoPermissionError || code == Int(EPERM) || code == Int(EACCES)
    }

    /// Mail message storage must never be offered as an app residual.
    /// ~/Library/Mail/Bundles stays allowed — Mail plugins are legitimate residuals.
    static func isProtectedMailPath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let home = homeDirectory
        let mailRoot = "\(home)/Library/Mail"
        let bundles = "\(home)/Library/Mail/Bundles"
        let mailContainer = "\(home)/Library/Containers/com.apple.mail"

        if path == mailContainer || path.hasPrefix(mailContainer + "/") { return true }
        if path == mailRoot { return true }
        if path.hasPrefix(mailRoot + "/") {
            return !(path == bundles || path.hasPrefix(bundles + "/"))
        }
        return false
    }

    static func isAndroidStudioDeveloperPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.hasSuffix("/.gradle") || lower.contains("/.gradle/") { return true }
        if lower.hasSuffix("/.android") || lower.contains("/.android/") { return true }
        if lower.contains("/library/android") { return true }
        return false
    }

    private func version(from url: URL) -> String {
        Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle(url: url)?.infoDictionary?["CFBundleVersion"] as? String
            ?? "version_unknown".localized
    }

    /// Physical size: what deleting the item actually frees. Sparse VM images
    /// (OrbStack data.img.raw) report tens of GB here, not their logical 500 GB.
    private func getDirectorySize(url: URL) async -> Int64 {
        fileManager.getPhysicalDirectorySize(url: url, excludedPaths: [])
    }

    public static func groupKey(for app: AppInfo) -> String {
        if let bundleID = app.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleID.isEmpty,
           !bundleID.lowercased().hasPrefix("unknown.") {
            return "bundleid:" + bundleID.lowercased()
        }
        return "name:" + app.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func aggregateRelatedFiles(from versions: [AppInfo]) -> [RelatedFile] {
        let allRelated = versions.flatMap(\.relatedFiles)
        return dedupAndSort(allRelated.map { ($0, $0.confidence) })
    }

    private func aggregateDeveloperComponents(from versions: [AppInfo]) -> [RelatedCleanupComponent] {
        var seen = Set<String>()
        var result: [RelatedCleanupComponent] = []
        for v in versions {
            for comp in v.developerComponents {
                let key = NormalizedPath.key(comp.url)
                if seen.insert(key).inserted {
                    result.append(comp)
                }
            }
        }
        return result
    }

    private func mergeApps(_ apps: [AppInfo]) -> [AppInfo] {
        var urlMap: [String: AppInfo] = [:]
        for app in apps {
            let key = NormalizedPath.key(app.url)
            if let existing = urlMap[key] {
                urlMap[key] = preferredApp(existing, app)
            } else {
                urlMap[key] = app
            }
        }
        let uniquePathApps = Array(urlMap.values)

        var groups: [String: [AppInfo]] = [:]
        for app in uniquePathApps {
            let key = Self.groupKey(for: app)
            groups[key, default: []].append(app)
        }

        var result: [AppInfo] = []
        for (_, groupApps) in groups {
            if groupApps.count == 1 {
                result.append(groupApps[0])
            } else {
                let sortedVersions = groupApps.sorted { preferredApp($0, $1) == $0 }
                let primary = sortedVersions[0]

                let versionStrings = sortedVersions.compactMap { $0.version.isEmpty ? nil : $0.version }
                let versionSummary = versionStrings.isEmpty ? primary.version : versionStrings.joined(separator: ", ")
                let latestLastUsed = sortedVersions.compactMap(\.lastUsed).max()

                let parent = AppInfo(
                    url: primary.url,
                    bundleID: primary.bundleID,
                    name: primary.name,
                    relatedFiles: aggregateRelatedFiles(from: sortedVersions),
                    developerComponents: aggregateDeveloperComponents(from: sortedVersions),
                    absorbedHelperURLs: NormalizedPath.unique(sortedVersions.flatMap(\.absorbedHelperURLs)),
                    identity: primary.identity,
                    scanState: sortedVersions.allSatisfy { $0.scanState == .deepScanned } ? .deepScanned : .discovered,
                    size: sortedVersions.reduce(0) { $0 + $1.size },
                    version: versionSummary,
                    lastUsed: latestLastUsed,
                    iconData: sortedVersions.compactMap(\.iconData).first,
                    versions: sortedVersions
                )
                result.append(parent)
            }
        }
        return result
    }

    private func preferredApp(_ lhs: AppInfo, _ rhs: AppInfo) -> AppInfo {
        let lhsIsStandard = lhs.url.path.hasPrefix("/Applications/")
        let rhsIsStandard = rhs.url.path.hasPrefix("/Applications/")
        if lhsIsStandard != rhsIsStandard {
            return rhsIsStandard ? rhs : lhs
        }

        let versionOrder = lhs.version.compare(rhs.version, options: .numeric)
        if versionOrder != .orderedSame {
            return versionOrder == .orderedAscending ? rhs : lhs
        }
        return lhs.url.path <= rhs.url.path ? lhs : rhs
    }

    private func dedupAndSort(_ items: [(file: RelatedFile, tier: ConfidenceTier)]) -> [RelatedFile] {
        let sortedByPath = items.map(\.file).sorted { $0.url.path.count < $1.url.path.count }
        var deduplicated: [String: RelatedFile] = [:]
        for file in sortedByPath {
            let pathKey = NormalizedPath.key(file.url)
            // Collapse into parent only when the parent is at least as confident;
            // a guaranteed child must not disappear inside an unselected possible parent.
            let coveredByParent = deduplicated.values.contains {
                pathKey.hasPrefix(NormalizedPath.key($0.url) + "/") && $0.confidence >= file.confidence
            }
            if coveredByParent { continue }

            if let existing = deduplicated[pathKey] {
                deduplicated[pathKey] = RelatedFile(
                    url: NormalizedPath.canonicalize(file.url),
                    isSelected: existing.isSelected || file.isSelected,
                    size: max(existing.size, file.size),
                    deletionRisk: existing.deletionRisk == .shared || file.deletionRisk == .shared
                        ? .shared
                        : (existing.deletionRisk == .normal || file.deletionRisk == .normal ? .normal : existing.deletionRisk),
                    evidence: existing.evidence.union(file.evidence),
                    confidence: max(existing.confidence, file.confidence)
                )
            } else {
                deduplicated[pathKey] = RelatedFile(
                    url: NormalizedPath.canonicalize(file.url),
                    isSelected: file.isSelected,
                    size: file.size,
                    deletionRisk: file.deletionRisk,
                    evidence: file.evidence,
                    confidence: file.confidence
                )
            }
        }
        return Array(deduplicated.values).sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return NormalizedPath.key(lhs.url) < NormalizedPath.key(rhs.url)
        }
    }
}
