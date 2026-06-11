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

    private let processManager: ProcessManager
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "ProcessesViewModel"
    )

    public var filteredProcesses: [RunningProcess] {
        guard !searchText.isEmpty else { return processes }
        let query = searchText.lowercased()
        return processes.filter {
            $0.name.lowercased().contains(query) ||
            $0.path?.lowercased().contains(query) == true
        }
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

    public func terminate(_ process: RunningProcess) async {
        lastError = nil
        do {
            try await processManager.terminate(process)
            lastKilledName = process.name
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
            await scan()
        } catch {
            lastError = error.localizedDescription
            logger.error("Graceful shutdown failed: \(error.localizedDescription)")
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
}
