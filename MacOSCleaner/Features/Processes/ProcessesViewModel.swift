import Foundation
import Observation
import os

@Observable
@MainActor
public final class ProcessesViewModel {
    public var processes: [RunningProcess] = []
    public var searchText: String = ""
    public var isLoading: Bool = false
    public var lastError: String? = nil
    public var confirmKill: RunningProcess? = nil
    public var confirmForceKill: RunningProcess? = nil
    public var lastKilledName: String? = nil
    public var blacklist: [String] = []
    public var whitelist: [String] = []
    public var showBlacklistAlert = false
    public var showWhitelistAlert = false
    public var newBlacklistEntry: String = ""
    public var newWhitelistEntry: String = ""
    public var permissions: [pid_t: KillPermission] = [:]
    public var selection: Set<pid_t> = []
    public var sortOption: ProcessSortOption = .cpu
    public var refreshInterval: RefreshInterval = .manual
    public var viewMode: ViewMode = .grouped
    public var expandedGroups: Set<String> = []

    private let processManager: ProcessManager
    private var refreshTask: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "ProcessesViewModel"
    )

    public enum ViewMode: String, CaseIterable, Identifiable {
        case grouped = "Grouped"
        case flat = "Flat"

        public var id: String { rawValue }
    }

    public var filteredProcesses: [RunningProcess] {
        let result: [RunningProcess]
        if searchText.isEmpty {
            result = processes
        } else {
            let query = searchText.lowercased()
            result = processes.filter {
                $0.name.lowercased().contains(query) ||
                $0.path?.lowercased().contains(query) == true ||
                $0.bundleID?.lowercased().contains(query) == true
            }
        }
        return result.sorted { a, b in
            switch sortOption {
            case .cpu:
                return a.cpuPercent > b.cpuPercent
            case .memory:
                return a.memoryBytes > b.memoryBytes
            case .name:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .threads:
                return a.threadCount > b.threadCount
            }
        }
    }

    public var processGroups: [ProcessGroup] {
        var groups = ProcessGroup.group(processes: filteredProcesses)
        return groups.map { group in
            var group = group
            if !searchText.isEmpty {
                group.isExpanded = true
            }
            return group
        }
    }

    public var userProcesses: [RunningProcess] {
        filteredProcesses.filter { $0.isUserProcess }
    }

    public var systemProcesses: [RunningProcess] {
        filteredProcesses.filter { !$0.isUserProcess }
    }

    public var memoryHogs: [RunningProcess] {
        processes
            .filter { $0.memoryBytes > 0 }
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(10)
            .map { $0 }
    }

    public var totalMemoryUsed: UInt64 {
        processes.reduce(0) { $0 + $1.memoryBytes }
    }

    public var totalMemoryFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalMemoryUsed), countStyle: .memory)
    }

    public init(processManager: ProcessManager = ProcessManager()) {
        self.processManager = processManager
    }

    public func scan() async {
        isLoading = true
        lastError = nil
        do {
            processes = try await processManager.listProcesses()
            var perms: [pid_t: KillPermission] = [:]
            for proc in processes {
                perms[proc.pid] = await processManager.checkPermission(proc)
            }
            permissions = perms
            let bl = Array(await processManager.getBlacklist()).sorted()
            let wl = Array(await processManager.getWhitelist()).sorted()
            blacklist = bl
            whitelist = wl
        } catch {
            lastError = error.localizedDescription
            logger.error("Scan failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    public func startAutoRefresh(interval: RefreshInterval) {
        stopAutoRefresh()
        refreshInterval = interval

        guard let timeInterval = interval.timeInterval else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(timeInterval))
                guard !Task.isCancelled else { break }
                await self?.scan()
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func terminate(_ process: RunningProcess) async {
        lastError = nil
        do {
            try await processManager.terminate(process)
            lastKilledName = process.name
            selection.remove(process.pid)
            await scan()
        } catch {
            lastError = error.localizedDescription
            logger.error("Terminate failed: \(error.localizedDescription)")
        }
    }

    public func forceKill(_ process: RunningProcess) async {
        lastError = nil
        do {
            try await processManager.forceKill(process)
            lastKilledName = process.name
            selection.remove(process.pid)
            await scan()
        } catch {
            lastError = error.localizedDescription
            logger.error("Force kill failed: \(error.localizedDescription)")
        }
    }

    public func gracefulShutdown(_ process: RunningProcess) async {
        lastError = nil
        do {
            try await processManager.gracefulShutdown(process)
            lastKilledName = process.name
            selection.remove(process.pid)
            await scan()
        } catch {
            lastError = error.localizedDescription
            logger.error("Graceful shutdown failed: \(error.localizedDescription)")
        }
    }

    public func terminateSelected() async {
        let selectedProcesses = processes.filter { selection.contains($0.pid) }
        for process in selectedProcesses {
            await terminate(process)
        }
        selection.removeAll()
    }

    public func forceKillSelected() async {
        let selectedProcesses = processes.filter { selection.contains($0.pid) }
        for process in selectedProcesses {
            await forceKill(process)
        }
        selection.removeAll()
    }

    public func terminateGroup(_ group: ProcessGroup) async {
        for process in group.processes {
            await terminate(process)
        }
    }

    public func forceKillGroup(_ group: ProcessGroup) async {
        for process in group.processes {
            await forceKill(process)
        }
    }

    public func addToBlacklist() async {
        let name = newBlacklistEntry.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await processManager.addToBlacklist(name)
        newBlacklistEntry = ""
        let bl = Array(await processManager.getBlacklist()).sorted()
        blacklist = bl
    }

    public func removeFromBlacklist(_ name: String) async {
        await processManager.removeFromBlacklist(name)
        let bl = Array(await processManager.getBlacklist()).sorted()
        blacklist = bl
    }

    public func addToWhitelist() async {
        let name = newWhitelistEntry.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await processManager.addToWhitelist(name)
        newWhitelistEntry = ""
        let wl = Array(await processManager.getWhitelist()).sorted()
        whitelist = wl
    }

    public func removeFromWhitelist(_ name: String) async {
        await processManager.removeFromWhitelist(name)
        let wl = Array(await processManager.getWhitelist()).sorted()
        whitelist = wl
    }

    public func checkPermission(_ process: RunningProcess) -> KillPermission {
        permissions[process.pid] ?? .allowed
    }

    public func toggleSelection(_ process: RunningProcess) {
        if selection.contains(process.pid) {
            selection.remove(process.pid)
        } else {
            selection.insert(process.pid)
        }
    }

    public func selectAll() {
        selection = Set(processes.map(\.pid))
    }

    public func deselectAll() {
        selection.removeAll()
    }

    public func toggleGroup(_ groupID: String) {
        if expandedGroups.contains(groupID) {
            expandedGroups.remove(groupID)
        } else {
            expandedGroups.insert(groupID)
        }
    }

    public func isGroupExpanded(_ groupID: String) -> Bool {
        expandedGroups.contains(groupID)
    }
}
