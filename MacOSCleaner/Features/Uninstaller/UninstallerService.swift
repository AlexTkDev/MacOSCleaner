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
        public var isSelected: Bool = true

        public init(title: String, category: CleanupCategory, sizeBytes: Int64, url: URL, isSelected: Bool = true) {
            self.title = title
            self.category = category
            self.sizeBytes = sizeBytes
            self.url = url
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
            self.url = url
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
        public let id = UUID()
        public let url: URL
        public let bundleID: String?
        public let name: String
        public var relatedFiles: [RelatedFile] = []
        public var developerComponents: [RelatedCleanupComponent] = []
        public var identity: AppIdentity?
        public var scanState: ScanState = .discovered

        public var size: Int64 = 0
        public var version: String = ""
        public var lastUsed: Date? = nil
        public var iconData: Data? = nil

        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
            lhs.id == rhs.id &&
            lhs.relatedFiles == rhs.relatedFiles &&
            lhs.developerComponents == rhs.developerComponents &&
            lhs.scanState == rhs.scanState &&
            lhs.size == rhs.size
        }

        public var totalSize: Int64 {
            let relatedSize = relatedFiles.filter(\.isSelected).reduce(0) { $0 + $1.size }
            let devSize = developerComponents.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
            return size + relatedSize + devSize
        }
    }

    // MARK: - Scan All Applications (Discovery only)

    public func scanAllApplications() async throws -> [AppInfo] {
        let discovery = AppDiscovery(commandRunner: commandRunner)
        let urls = await discovery.findAll()

        await MainActor.run {
            progress.currentStep = 0
            progress.totalSteps = urls.count
            progress.message = "uninstaller.progress.discovering".localized
            progress.percentage = 0.0
        }

        return try await withThrowingTaskGroup(of: AppInfo?.self) { group in
            for url in urls {
                group.addTask {
                    let app = try? await self.discoverAndIndex(url)
                    await MainActor.run {
                        self.progress.currentStep += 1
                        self.progress.percentage = Double(self.progress.currentStep) / Double(self.progress.totalSteps)
                    }
                    return app
                }
            }

            var apps: [AppInfo] = []
            for try await app in group {
                if let app = app { apps.append(app) }
            }

            let merged = mergeApps(apps)

            await MainActor.run {
                progress.message = "uninstaller.progress.complete".localized
                progress.percentage = 1.0
            }

            return merged.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
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
            url: url,
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
        updated.relatedFiles = related
        updated.developerComponents = developer
        updated.scanState = .deepScanned

        return updated
    }

    private func runDeepRelatedFiles(identity: AppIdentity, graph: EvidenceGraph, mode: ScanMode = .balanced) async -> [RelatedFile] {
        let collector = CandidateCollector(commandRunner: commandRunner)
        let collection = await collector.collectDetailed(identity: identity, mode: mode)
        let probe = EvidenceProbe(commandRunner: commandRunner, codesignCache: codesignCache, plistCache: plistCache)

        // Record evidence
        for url in collection.candidates {
            var evidences = await probe.probe(url: url, identity: identity)
            if collection.receiptPaths.contains(url) {
                evidences.insert(.packageReceipt)
            }
            if collection.catalogPaths.contains(url) {
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
                // Weak matches are shown but never pre-selected for deletion
                isSelected: assessment.tier >= .veryLikely,
                size: fileSize,
                deletionRisk: risk,
                evidence: assessment.evidence,
                confidence: assessment.tier
            )
            related.append((file, assessment.tier))
        }

        // Dedup by prefix, sort by tier then path
        return dedupAndSort(related)
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
        try await discoverAndIndex(appURL)
    }

    // MARK: - Uninstall

    public func uninstall(app: AppInfo, bypassTrash: Bool = false, emptyTrashImmediately: Bool = false) async throws {
        Logger.uninstaller.info("Uninstalling '\(app.name, privacy: .public)' bypassTrash=\(bypassTrash)")

        let relatedTargets = app.relatedFiles.filter(\.isSelected).map(\.url)
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

        if bypassTrash {
            try safetyManager.validate(url: app.url, policy: .uninstall)
            do {
                try fileManager.removeItem(at: app.url)
                Logger.uninstaller.info("Permanently removed: \(app.url.path, privacy: .public)")
            } catch {
                Logger.uninstaller.error("removeItem failed '\(app.url.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                throw error
            }
            for target in deletionTargets {
                do {
                    try safetyManager.validate(url: target, policy: .uninstall)
                    try fileManager.removeItem(at: target)
                    Logger.uninstaller.debug("Removed: \(target.path, privacy: .public)")
                } catch {
                    Logger.uninstaller.warning("removeItem failed '\(target.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            do {
                _ = try await trashManager.trashItem(at: app.url, policy: .uninstall)
                Logger.uninstaller.info("Trashed: \(app.url.path, privacy: .public)")
            } catch {
                Logger.uninstaller.error("trashItem failed '\(app.url.path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                throw error
            }
            for target in deletionTargets {
                do {
                    _ = try await trashManager.trashItem(at: target, policy: .uninstall)
                    Logger.uninstaller.debug("Trashed: \(target.path, privacy: .public)")
                } catch {
                    Logger.uninstaller.warning("trashItem related '\(target.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if let bundleID = app.bundleID {
            do {
                _ = try await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--forget", bundleID])
                Logger.uninstaller.debug("pkgutil --forget \(bundleID, privacy: .public)")
            } catch {
                Logger.uninstaller.warning("pkgutil --forget '\(bundleID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        if emptyTrashImmediately {
            do {
                try await trashManager.requestTrashAccess()
                _ = try await trashManager.emptyTrash()
            } catch {
                Logger.uninstaller.error("emptyTrash failed: \(error.localizedDescription, privacy: .public)")
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

    /// Mail message storage must never be offered as an app residual.
    /// ~/Library/Mail/Bundles stays allowed — Mail plugins are legitimate residuals.
    static func isProtectedMailPath(_ path: String) -> Bool {
        let home = NSHomeDirectory()
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

    private func mergeApps(_ apps: [AppInfo]) -> [AppInfo] {
        var merged: [String: AppInfo] = [:]
        for app in apps {
            let key = "\(app.bundleID ?? "")-\(app.name)"
            if let existing = merged[key] {
                merged[key] = preferredApp(existing, app)
            } else {
                merged[key] = app
            }
        }
        return Array(merged.values)
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
        var deduplicated: [URL: RelatedFile] = [:]
        for file in sortedByPath {
            // Collapse into parent only when the parent is at least as confident;
            // a guaranteed child must not disappear inside an unselected possible parent.
            let coveredByParent = deduplicated.values.contains {
                file.url.path.hasPrefix($0.url.path + "/") && $0.confidence >= file.confidence
            }
            if !coveredByParent {
                deduplicated[file.url] = file
            }
        }
        return Array(deduplicated.values).sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.url.path < rhs.url.path
        }
    }
}
