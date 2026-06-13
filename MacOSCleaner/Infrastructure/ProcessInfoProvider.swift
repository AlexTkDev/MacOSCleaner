import Foundation
import os

public actor ProcessInfoProvider {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "ProcessInfoProvider"
    )

    public init() {}

    public func listAllProcesses() async throws -> [RunningProcess] {
        let pids = try listPIDs()
        return try await withThrowingTaskGroup(of: RunningProcess?.self) { group in
            for pid in pids {
                group.addTask { [self] in
                    try await self.processInfo(for: pid)
                }
            }
            var results: [RunningProcess] = []
            for try await info in group {
                if let info {
                    results.append(info)
                }
            }
            return results.sorted { $0.pid < $1.pid }
        }
    }

    private func listPIDs() throws -> [pid_t] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0) / Int32(MemoryLayout<pid_t>.size)
        guard bufferSize > 0 else {
            throw ProcessInfoError.listPIDsFailed
        }

        var pidBuffer = [pid_t](repeating: 0, count: Int(bufferSize))
        let actualSize = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0,
            &pidBuffer, Int32(bufferSize * Int32(MemoryLayout<pid_t>.size))
        )
        let count = Int(actualSize) / MemoryLayout<pid_t>.size

        return Array(pidBuffer.prefix(count))
    }

    private func processInfo(for pid: pid_t) async throws -> RunningProcess? {
        guard pid > 0 else { return nil }

        let path = getPath(for: pid)
        let taskInfo = getTaskInfo(for: pid)
        let bsdInfo = getBSDInfo(for: pid)

        let name: String
        if let bsdInfo {
            name = withUnsafePointer(to: bsdInfo.pbi_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }
        } else if let path {
            name = URL(fileURLWithPath: path).lastPathComponent
        } else {
            return nil
        }

        let cpuPercent: Double = {
            guard let info = taskInfo else { return 0 }
            let total = info.pti_total_user + info.pti_total_system
            let nanoseconds = UInt64(total)
            return Double(nanoseconds) / 1_000_000_000.0
        }()

        let memoryBytes: UInt64 = {
            guard let info = taskInfo else { return 0 }
            return info.pti_resident_size
        }()

        let threadCount: Int = {
            guard let info = taskInfo else { return 0 }
            return Int(info.pti_threadnum)
        }()

        let startTime: Date? = {
            guard let info = bsdInfo else { return nil }
            let seconds = info.pbi_start_tvsec
            let microseconds = info.pbi_start_tvusec
            return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(microseconds) / 1_000_000.0)
        }()

        let parentPID: pid_t = {
            guard let info = bsdInfo else { return 0 }
            return pid_t(info.pbi_ppid)
        }()

        let bundleID: String? = {
            guard let path else { return nil }
            return getBundleID(for: path)
        }()

        return RunningProcess(
            pid: pid,
            name: name,
            path: path,
            user: nil,
            cpuPercent: cpuPercent,
            memoryBytes: memoryBytes,
            threadCount: threadCount,
            startTime: startTime,
            parentPID: parentPID,
            bundleID: bundleID
        )
    }

    private func getPath(for pid: pid_t) -> String? {
        let pathSize = 4 * Int(MAXPATHLEN)
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: pathSize)
        defer { pathBuffer.deallocate() }

        let pathLength = proc_pidpath(pid, pathBuffer, UInt32(pathSize))
        guard pathLength > 0 else { return nil }

        return String(cString: pathBuffer)
    }

    private func getTaskInfo(for pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = proc_pidinfo(
            pid, PROC_PIDTASKINFO, 0,
            &info, Int32(MemoryLayout<proc_taskinfo>.size)
        )
        return size == Int32(MemoryLayout<proc_taskinfo>.size) ? info : nil
    }

    private func getBSDInfo(for pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(
            pid, PROC_PIDTBSDINFO, 0,
            &info, Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        return size == Int32(MemoryLayout<proc_bsdinfo>.size) ? info : nil
    }

    private func getBundleID(for path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return Bundle(path: path)?.bundleIdentifier
    }
}

public enum ProcessInfoError: Error, LocalizedError {
    case listPIDsFailed

    public var errorDescription: String? {
        switch self {
        case .listPIDsFailed:
            return "Failed to list process IDs"
        }
    }
}
