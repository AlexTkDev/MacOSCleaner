import Foundation
import Observation
import OSLog

private extension Logger {
    static let uninstallerVM = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "UninstallerViewModel")
}

@MainActor
@Observable
public final class UninstallerViewModel {
    public let service: UninstallerService

    // Applications tab state
    var selectedTab: UninstallerTab = .applications
    public var allApps: [UninstallerService.AppInfo] = []
    public var selectedApp: UninstallerService.AppInfo?
    public var searchText = ""
    public var isLoading = false
    public var isUninstalling = false
    public var uninstallingAppName = ""
    public var isDeepScanning = false
    public var deepScanCompleted = 0
    public var deepScanTotal = 0
    public var expandedConfidenceTiers: Set<ConfidenceTier> = [.guaranteed, .veryLikely, .possible]
    public var selectedVersionID: UUID? = nil
    public var postUninstallReport: VerificationReport? = nil
    public var showingPostUninstallSheet = false
    public var uninstallErrorMessage: String? = nil
    public var showingUninstallErrorAlert = false
    public var showingRestartBanner = false
    public var isSpotlightAvailable: Bool = true
    public var lastUpdatedAt: Date? = nil

    // Leftovers tab state
    public var orphanItems: [OrphanItem] = []
    public var isLoadingOrphans = false
    public var hasScannedOrphans = false
    public var orphanScanProgressMessage = ""
    public var orphanSearchText = ""
    public var orphanFilterTier: ConfidenceTier? = nil
    public var expandedOrphanIDs: Set<UUID> = []
    public var isCleaningOrphans = false
    public var orphanErrorMessage: String? = nil
    public var showingOrphanErrorAlert = false

    private var deepScanCache: [String: UninstallerService.AppInfo] = [:]
    private var activeScanIndex: ResidualScanIndex?
    private var scanTask: Task<Void, Never>?
    private var priorityDeepScanTask: Task<Void, Never>?
    private var orphanScanTask: Task<Void, Never>?
    private let discoverAppsHandler: (@Sendable () async throws -> [UninstallerService.AppInfo])?
    private let deepScanHandler: (@Sendable (UninstallerService.AppInfo, ScanMode) async throws -> UninstallerService.AppInfo)?

    public init(
        service: UninstallerService = UninstallerService(),
        discoverAppsHandler: (@Sendable () async throws -> [UninstallerService.AppInfo])? = nil,
        deepScanHandler: (@Sendable (UninstallerService.AppInfo, ScanMode) async throws -> UninstallerService.AppInfo)? = nil
    ) {
        self.service = service
        self.discoverAppsHandler = discoverAppsHandler
        self.deepScanHandler = deepScanHandler
    }

    public var filteredApps: [UninstallerService.AppInfo] {
        if searchText.isEmpty {
            return allApps
        }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    public func sameAppURL(_ lhs: URL, _ rhs: URL) -> Bool {
        NormalizedPath.key(lhs) == NormalizedPath.key(rhs)
    }

    public func refreshSpotlightAvailability() {
        Task { [weak self] in
            let available = await Task.detached(priority: .utility) {
                SpotlightMetadata.isIndexingAvailable()
            }.value
            self?.isSpotlightAvailable = available
        }
    }

    public func loadAppsIfNeeded(mode: ScanMode) {
        refreshSpotlightAvailability()
        guard lastUpdatedAt == nil, allApps.isEmpty, !isLoading else { return }
        loadApps(mode: mode)
    }

    public func loadApps(mode: ScanMode) {
        scanTask?.cancel()
        priorityDeepScanTask?.cancel()
        refreshSpotlightAvailability()
        isLoading = true
        isDeepScanning = false
        deepScanCompleted = 0
        deepScanTotal = 0
        deepScanCache.removeAll()
        activeScanIndex = nil

        let discover = discoverAppsHandler
        let deepScanRunner = deepScanHandler
        let service = self.service

        scanTask = Task {
            let fresh: [UninstallerService.AppInfo]
            if let discover {
                fresh = (try? await discover()) ?? []
            } else {
                fresh = (try? await service.scanAllApplications()) ?? []
            }
            guard !Task.isCancelled else { return }

            allApps = fresh
            lastUpdatedAt = Date()
            isLoading = false

            let total = fresh.count
            guard total > 0 else { return }

            isDeepScanning = true
            deepScanCompleted = 0
            deepScanTotal = total

            let scanIndex: ResidualScanIndex?
            if deepScanRunner == nil {
                let built = await Task.detached(priority: .utility) {
                    await service.buildResidualScanIndex()
                }.value
                guard !Task.isCancelled else { return }
                activeScanIndex = built
                scanIndex = built
            } else {
                scanIndex = nil
            }

            let maxConcurrent = 4
            var iterator = fresh.makeIterator()

            await withTaskGroup(of: (UninstallerService.AppInfo, UninstallerService.AppInfo?).self) { group in
                for _ in 0..<maxConcurrent {
                    guard !Task.isCancelled,
                          let next = nextPendingDeepScanApp(from: &iterator) else { break }
                    group.addTask {
                        if let deepScanRunner {
                            return (next, try? await deepScanRunner(next, mode))
                        }
                        return (next, try? await service.deepScan(next, mode: mode, scanIndex: scanIndex))
                    }
                }

                for await (app, scanned) in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    if let existingIdx = allApps.firstIndex(where: { $0.id == app.id || sameAppURL($0.url, app.url) }),
                       allApps[existingIdx].scanState == .deepScanned {
                        deepScanCompleted = min(deepScanTotal, deepScanCompleted + 1)
                    } else {
                        if let scanned {
                            applyDeepScanResult(scanned)
                        }
                        deepScanCompleted = min(deepScanTotal, deepScanCompleted + 1)
                    }
                    if let next = nextPendingDeepScanApp(from: &iterator) {
                        group.addTask {
                            if let deepScanRunner {
                                return (next, try? await deepScanRunner(next, mode))
                            }
                            return (next, try? await service.deepScan(next, mode: mode, scanIndex: scanIndex))
                        }
                    }
                }
            }

            if !Task.isCancelled {
                activeScanIndex = nil
                isDeepScanning = false
            }
        }
    }

    public func selectApp(_ app: UninstallerService.AppInfo, mode: ScanMode) {
        selectedVersionID = nil
        if let latest = allApps.first(where: { $0.id == app.id || sameAppURL($0.url, app.url) }) {
            selectedApp = latest
        } else {
            selectedApp = app
        }
        guard let current = selectedApp, current.scanState != .deepScanned else { return }

        let key = NormalizedPath.key(current.url)
        if let cached = deepScanCache[key] {
            applyDeepScanResult(cached)
            return
        }

        priorityDeepScanTask?.cancel()
        let service = self.service
        let deepScanRunner = self.deepScanHandler
        let scanIndex = self.activeScanIndex
        priorityDeepScanTask = Task {
            let result: UninstallerService.AppInfo?
            if let deepScanRunner {
                result = try? await deepScanRunner(current, mode)
            } else {
                result = try? await service.deepScan(current, mode: mode, scanIndex: scanIndex)
            }
            guard !Task.isCancelled, let result else { return }
            applyDeepScanResult(result)
        }
    }

    public func dropApp(at url: URL, mode: ScanMode) {
        Task {
            if let scanned = try? await service.scan(appURL: url) {
                let deep = (try? await service.deepScan(scanned, mode: mode)) ?? scanned
                self.selectedVersionID = nil
                self.selectedApp = deep
            }
        }
    }

    public func uninstall(_ app: UninstallerService.AppInfo, settings: AppSettings) {
        uninstallingAppName = app.name
        isUninstalling = true
        let mode = settings.uninstallerScanMode
        let bypassTrash = settings.bypassTrashOnUninstall
        let emptyTrash = settings.emptyTrashDuringCleanup
        let removeFromDock = settings.removeFromDockOnUninstall
        let showNotifications = settings.showNotifications
        let candidateURLs = Self.selectedRemovalURLs(for: app)

        Task {
            defer { isUninstalling = false }
            do {
                let report = try await service.uninstall(
                    app: app,
                    bypassTrash: bypassTrash,
                    emptyTrashImmediately: emptyTrash,
                    removeFromDock: removeFromDock
                )

                updateRestartBanner(for: candidateURLs, report: report)

                loadApps(mode: mode)
                selectedApp = nil
                if let report, report.hasLeftovers || !report.failedDeletions.isEmpty {
                    postUninstallReport = report
                    showingPostUninstallSheet = true
                } else if showNotifications {
                    let title = "uninstaller_complete_title".localized
                    let body = String(format: "uninstaller_complete_body".localized, app.name)
                    NotificationManager.shared.sendNotification(title: title, body: body)
                }
            } catch {
                Logger.uninstallerVM.error("Uninstall failed: \(error.localizedDescription, privacy: .public)")
                uninstallErrorMessage = error.localizedDescription
                showingUninstallErrorAlert = true
            }
        }
    }

    public func uninstallVersion(_ versionApp: UninstallerService.AppInfo, from parentApp: UninstallerService.AppInfo, settings: AppSettings) {
        uninstallingAppName = "\(parentApp.name) v\(versionApp.version)"
        isUninstalling = true
        let bypassTrash = settings.bypassTrashOnUninstall
        let emptyTrash = settings.emptyTrashDuringCleanup
        let removeFromDock = settings.removeFromDockOnUninstall
        let showNotifications = settings.showNotifications
        let candidateURLs = Self.selectedRemovalURLs(for: versionApp)

        Task {
            defer { isUninstalling = false }
            do {
                let report = try await service.uninstall(
                    app: versionApp,
                    bypassTrash: bypassTrash,
                    emptyTrashImmediately: emptyTrash,
                    removeFromDock: removeFromDock
                )

                updateRestartBanner(for: candidateURLs, report: report)

                if let report, report.hasLeftovers || !report.failedDeletions.isEmpty {
                    postUninstallReport = report
                    showingPostUninstallSheet = true
                } else if showNotifications {
                    let title = "uninstaller_complete_title".localized
                    let body = String(format: "uninstaller_version_deleted_body".localized, versionApp.version, parentApp.name)
                    NotificationManager.shared.sendNotification(title: title, body: body)
                }

                let remaining = parentApp.versions.filter { !sameAppURL($0.url, versionApp.url) }
                if remaining.isEmpty {
                    allApps.removeAll { $0.id == parentApp.id }
                    selectedApp = nil
                } else if remaining.count == 1 {
                    var updatedParent = remaining[0]
                    updatedParent.versions = []
                    if let idx = allApps.firstIndex(where: { $0.id == parentApp.id }) {
                        allApps[idx] = updatedParent
                    }
                    selectedApp = updatedParent
                } else {
                    var updatedParent = parentApp
                    updatedParent.versions = remaining
                    updatedParent.size = remaining.reduce(0) { $0 + $1.size }
                    if let idx = allApps.firstIndex(where: { $0.id == parentApp.id }) {
                        allApps[idx] = updatedParent
                    }
                    selectedApp = updatedParent
                }
            } catch {
                Logger.uninstallerVM.error("Uninstall version failed: \(error.localizedDescription, privacy: .public)")
                uninstallErrorMessage = error.localizedDescription
                showingUninstallErrorAlert = true
            }
        }
    }

    public func cleanPostUninstallLeftovers(_ items: [LeftoverItem], settings: AppSettings) {
        guard !items.isEmpty else {
            showingPostUninstallSheet = false
            postUninstallReport = nil
            return
        }
        let bypassTrash = settings.bypassTrashOnUninstall
        let showNotifications = settings.showNotifications
        Task {
            do {
                let freed = try await service.removeLeftovers(items, bypassTrash: bypassTrash)
                let removedURLs = items.map(\.url).filter { !FileManager.default.fileExists(atPath: $0.path) }
                if UninstallerService.requiresRestartForRemovedPaths(removedURLs) {
                    showingRestartBanner = true
                }
                self.showingPostUninstallSheet = false
                self.postUninstallReport = nil
                if showNotifications {
                    let title = "uninstaller_complete_title".localized
                    let body = String(
                        format: "uninstaller_leftovers_cleaned_notification".localized,
                        Int64(items.count),
                        ByteCountFormatter.localizedString(fromByteCount: freed, countStyle: .file)
                    )
                    NotificationManager.shared.sendNotification(title: title, body: body)
                }
            } catch {
                Logger.uninstallerVM.error("Failed to clean leftovers: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func updateRestartBanner(for candidateURLs: [URL], report: VerificationReport?) {
        let failedKeys = Set((report?.failedDeletions ?? []).map { NormalizedPath.key($0.url) })
        let removedURLs = candidateURLs.filter { !failedKeys.contains(NormalizedPath.key($0)) }
        if UninstallerService.requiresRestartForRemovedPaths(removedURLs) {
            showingRestartBanner = true
        }
    }

    private static func selectedRemovalURLs(for app: UninstallerService.AppInfo) -> [URL] {
        if !app.versions.isEmpty {
            return app.versions.flatMap { selectedRemovalURLs(for: $0) }
        }
        return [app.url]
            + app.relatedFiles.filter(\.isSelected).map(\.url)
            + app.developerComponents.filter(\.isSelected).map(\.url)
    }

    public func toggleSelection(_ file: UninstallerService.RelatedFile, in app: UninstallerService.AppInfo) {
        if let appIndex = allApps.firstIndex(where: { $0.id == app.id }),
           let fileIndex = allApps[appIndex].relatedFiles.firstIndex(where: { $0.id == file.id }) {
            allApps[appIndex].relatedFiles[fileIndex].isSelected.toggle()
            let updated = allApps[appIndex]
            deepScanCache[NormalizedPath.key(updated.url)] = updated
            if selectedApp?.id == app.id {
                selectedApp = updated
            }
            return
        }
        if var current = selectedApp, current.id == app.id,
           let fileIndex = current.relatedFiles.firstIndex(where: { $0.id == file.id }) {
            current.relatedFiles[fileIndex].isSelected.toggle()
            deepScanCache[NormalizedPath.key(current.url)] = current
            selectedApp = current
        }
    }

    public func toggleDeveloperComponent(in app: UninstallerService.AppInfo, at index: Int, value: Bool) {
        if let appIndex = allApps.firstIndex(where: { $0.id == app.id }),
           allApps[appIndex].developerComponents.indices.contains(index) {
            allApps[appIndex].developerComponents[index].isSelected = value
            let updated = allApps[appIndex]
            deepScanCache[NormalizedPath.key(updated.url)] = updated
            if selectedApp?.id == app.id {
                selectedApp = updated
            }
            return
        }
        if var current = selectedApp, current.id == app.id,
           current.developerComponents.indices.contains(index) {
            current.developerComponents[index].isSelected = value
            deepScanCache[NormalizedPath.key(current.url)] = current
            selectedApp = current
        }
    }

    // MARK: - Orphans

    public func startOrphanScan() {
        orphanScanTask?.cancel()
        isLoadingOrphans = true
        orphanScanProgressMessage = "uninstaller.progress.discovering".localized

        let service = self.service
        orphanScanTask = Task {
            do {
                let found = try await service.scanOrphanedResiduals { message in
                    Task { @MainActor in
                        self.orphanScanProgressMessage = message
                    }
                }
                guard !Task.isCancelled else { return }
                self.orphanItems = found
                self.isLoadingOrphans = false
                self.hasScannedOrphans = true
            } catch {
                Logger.uninstallerVM.error("Orphan scan failed: \(error.localizedDescription, privacy: .public)")
                self.isLoadingOrphans = false
                self.hasScannedOrphans = true
            }
        }
    }

    public func cleanSelectedOrphans(_ targets: [OrphanItem], settings: AppSettings) {
        guard !targets.isEmpty else { return }
        isCleaningOrphans = true
        let bypassTrash = settings.bypassTrashOnUninstall
        let showNotifications = settings.showNotifications

        Task {
            defer { isCleaningOrphans = false }
            do {
                let result = try await service.removeOrphanedResiduals(targets, bypassTrash: bypassTrash)
                let removedIDs = Set(result.succeededItems.map(\.id))
                self.orphanItems.removeAll { removedIDs.contains($0.id) }
                if UninstallerService.requiresRestartForRemovedPaths(result.succeededItems.map(\.url)) {
                    self.showingRestartBanner = true
                }

                if !result.failedItems.isEmpty {
                    self.orphanErrorMessage = String(format: "orphaned_cleanup_failed_count".localized, Int64(result.failedItems.count))
                    self.showingOrphanErrorAlert = true
                }

                if showNotifications, !result.succeededItems.isEmpty {
                    let title = "uninstaller_complete_title".localized
                    let body = String(
                        format: "uninstaller_leftovers_cleaned_notification".localized,
                        Int64(result.succeededItems.count),
                        ByteCountFormatter.localizedString(fromByteCount: result.freed, countStyle: .file)
                    )
                    NotificationManager.shared.sendNotification(title: title, body: body)
                }
            } catch {
                Logger.uninstallerVM.error("Cleaning orphans failed: \(error.localizedDescription, privacy: .public)")
                self.orphanErrorMessage = error.localizedDescription
                self.showingOrphanErrorAlert = true
            }
        }
    }

    private func nextPendingDeepScanApp(
        from iterator: inout IndexingIterator<[UninstallerService.AppInfo]>
    ) -> UninstallerService.AppInfo? {
        while !Task.isCancelled {
            guard let next = iterator.next() else { return nil }
            let key = NormalizedPath.key(next.url)
            if let existingIdx = allApps.firstIndex(where: { $0.id == next.id || sameAppURL($0.url, next.url) }),
               allApps[existingIdx].scanState == .deepScanned {
                deepScanCompleted = min(deepScanTotal, deepScanCompleted + 1)
                continue
            }
            if let alreadyScanned = deepScanCache[key] {
                applyDeepScanResult(alreadyScanned)
                deepScanCompleted = min(deepScanTotal, deepScanCompleted + 1)
                continue
            }
            return next
        }
        return nil
    }

    private func applyDeepScanResult(_ result: UninstallerService.AppInfo) {
        deepScanCache[NormalizedPath.key(result.url)] = result
        if let idx = allApps.firstIndex(where: { $0.id == result.id || sameAppURL($0.url, result.url) }) {
            allApps[idx] = result
        }
        if let selected = selectedApp, selected.id == result.id || sameAppURL(selected.url, result.url) {
            selectedApp = result
        }
    }
}
