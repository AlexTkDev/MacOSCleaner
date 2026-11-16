import AppKit
import Foundation
import Observation

public enum NetworkFilterMode: String, CaseIterable, Identifiable {
    case activeSockets
    case staticCapabilities
    case restricted

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .activeSockets: return "privacy_net_filter_active".localized
        case .staticCapabilities: return "privacy_net_filter_static".localized
        case .restricted: return "privacy_net_filter_restricted".localized
        }
    }
}

public enum PendingTCCReset: Identifiable {
    case single(entry: TCCPermissionEntry, group: TCCAppGroup)
    case allForApp(group: TCCAppGroup)

    public var id: String {
        switch self {
        case .single(let entry, _): return "single|\(entry.id)"
        case .allForApp(let group): return "all|\(group.client)"
        }
    }

    public var bundleID: String {
        switch self {
        case .single(_, let group): return group.client
        case .allForApp(let group): return group.client
        }
    }

    public var appName: String {
        switch self {
        case .single(_, let group): return group.appName
        case .allForApp(let group): return group.appName
        }
    }

    public var serviceTitle: String {
        switch self {
        case .single(let entry, _): return entry.service.localizedTitle
        case .allForApp: return "privacy_tcc_all_user_permissions".localized
        }
    }

    public var isAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
    }
}

@MainActor
@Observable
public final class PrivacyViewModel {
    private let tccService: TCCService
    private let networkService: NetworkSnapshotService
    private let extensionScanner: BrowserExtensionScanner

    public var selectedTab: PrivacyTab = .tcc
    public var searchText: String = ""

    // TCC
    public var tccSnapshot: TCCSnapshot? = nil
    public var isLoadingTCC: Bool = false
    public var tccServiceFilter: TCCPermissionService? = nil
    public var pendingReset: PendingTCCReset? = nil
    public var isResettingTCC: Bool = false
    public var sessionLog: [TCCSessionLogEntry] = []

    // Network
    public var networkSnapshot: NetworkSnapshot? = nil
    public var isLoadingNetwork: Bool = false
    public var networkFilterMode: NetworkFilterMode = .activeSockets

    // Extensions
    public var extensions: [BrowserExtensionItem] = []
    public var isLoadingExtensions: Bool = false
    public var browserFilter: ExtensionBrowser? = nil

    // Feedback
    public var actionNotice: String? = nil
    public var errorMessage: String? = nil

    public init(
        tccService: TCCService = TCCService(),
        networkService: NetworkSnapshotService = NetworkSnapshotService(),
        extensionScanner: BrowserExtensionScanner = BrowserExtensionScanner()
    ) {
        self.tccService = tccService
        self.networkService = networkService
        self.extensionScanner = extensionScanner
    }

    // MARK: - Filtered Computed Collections

    public var availableTCCServices: [TCCPermissionService] {
        guard let groups = tccSnapshot?.groups else { return [] }
        let unique = Set(groups.flatMap { $0.entries.map(\.service) })
        return unique.sorted {
            $0.localizedTitle.localizedCaseInsensitiveCompare($1.localizedTitle) == .orderedAscending
        }
    }

    public var filteredTCCGroups: [TCCAppGroup] {
        guard let groups = tccSnapshot?.groups else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return groups.compactMap { group in
            let matchesQuery = query.isEmpty
                || group.appName.lowercased().contains(query)
                || group.client.lowercased().contains(query)
            guard matchesQuery else { return nil }

            let matchingEntries: [TCCPermissionEntry]
            if let serviceFilter = tccServiceFilter {
                matchingEntries = group.entries.filter { $0.service == serviceFilter }
            } else {
                matchingEntries = group.entries
            }
            guard !matchingEntries.isEmpty else { return nil }

            return TCCAppGroup(
                client: group.client,
                appName: group.appName,
                appURL: group.appURL,
                appIdentity: group.appIdentity,
                isRunning: group.isRunning,
                entries: matchingEntries
            )
        }
    }

    public var filteredNetworkItems: [AppNetworkItem] {
        guard let items = networkSnapshot?.items else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return items.filter { item in
            let matchesMode: Bool
            switch networkFilterMode {
            case .activeSockets:
                matchesMode = !item.sockets.isEmpty
            case .staticCapabilities:
                matchesMode = item.staticProfile?.hasAnyCapability == true
            case .restricted:
                matchesMode = item.isRestrictedByPermissions
            }
            guard matchesMode else { return false }
            guard !query.isEmpty else { return true }
            return item.name.lowercased().contains(query)
                || (item.bundleID?.lowercased().contains(query) ?? false)
                || item.sockets.contains {
                    $0.local.displayString.lowercased().contains(query)
                        || ($0.remote?.displayString.lowercased().contains(query) ?? false)
                }
        }
    }

    public var filteredExtensions: [BrowserExtensionItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return extensions.filter { item in
            if let browserFilter, item.browser != browserFilter {
                return false
            }
            guard !query.isEmpty else { return true }
            return item.name.lowercased().contains(query)
                || item.extensionID.lowercased().contains(query)
                || item.browser.displayName.lowercased().contains(query)
        }
    }

    // MARK: - Actions

    public func refreshCurrentTab() async {
        actionNotice = nil
        errorMessage = nil
        switch selectedTab {
        case .tcc:
            await loadTCC()
        case .network:
            await captureNetworkSnapshot()
        case .extensions:
            await loadExtensions()
        }
    }

    public func loadTCCIfNeeded() async {
        if tccSnapshot == nil && !isLoadingTCC {
            await loadTCC()
        }
    }

    public func loadTCC() async {
        isLoadingTCC = true
        errorMessage = nil
        tccSnapshot = await tccService.loadSnapshot()
        isLoadingTCC = false
    }

    public func confirmReset(quitAppFirst: Bool) async {
        guard let target = pendingReset else { return }
        pendingReset = nil
        isResettingTCC = true
        errorMessage = nil
        actionNotice = nil
        defer { isResettingTCC = false }

        if quitAppFirst {
            let handles = NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == target.bundleID && !$0.isTerminated }
                .map { AppQuitter.Handle(application: $0) }
            if !handles.isEmpty {
                _ = await AppQuitter.quit(handles)
            }
        }

        do {
            let updated: TCCSnapshot
            switch target {
            case .single(let entry, _):
                updated = try await tccService.resetPermission(entry)
            case .allForApp(let group):
                updated = try await tccService.resetAllPermissions(for: group)
            }
            tccSnapshot = updated
            let msg = String(format: "privacy_tcc_reset_success".localized, target.serviceTitle, target.appName)
            actionNotice = msg
            sessionLog.insert(
                TCCSessionLogEntry(
                    timestamp: Date(),
                    client: target.bundleID,
                    appName: target.appName,
                    serviceTitle: target.serviceTitle,
                    succeeded: true,
                    message: msg
                ),
                at: 0
            )
        } catch {
            let msg = error.localizedDescription
            errorMessage = msg
            sessionLog.insert(
                TCCSessionLogEntry(
                    timestamp: Date(),
                    client: target.bundleID,
                    appName: target.appName,
                    serviceTitle: target.serviceTitle,
                    succeeded: false,
                    message: msg
                ),
                at: 0
            )
        }
    }

    public func captureNetworkSnapshotIfNeeded() async {
        if networkSnapshot == nil && !isLoadingNetwork {
            await captureNetworkSnapshot()
        }
    }

    public func captureNetworkSnapshot() async {
        isLoadingNetwork = true
        errorMessage = nil
        do {
            networkSnapshot = try await networkService.captureSnapshot(includeStaticApps: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingNetwork = false
    }

    public func loadExtensionsIfNeeded() async {
        if extensions.isEmpty && !isLoadingExtensions {
            await loadExtensions()
        }
    }

    public func loadExtensions() async {
        isLoadingExtensions = true
        errorMessage = nil
        extensions = await extensionScanner.scanAll()
        isLoadingExtensions = false
    }

    public func openExtensionInBrowser(_ item: BrowserExtensionItem) async {
        actionNotice = await BrowserExtensionScanner.openInBrowser(item)
    }
}
