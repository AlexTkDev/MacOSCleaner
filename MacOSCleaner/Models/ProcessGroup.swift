import Foundation

public struct ProcessGroup: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let icon: String
    public var processes: [RunningProcess]
    public var isExpanded: Bool

    public init(
        id: String,
        displayName: String,
        icon: String = "app.fill",
        processes: [RunningProcess],
        isExpanded: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.processes = processes
        self.isExpanded = isExpanded
    }

    public var totalCPU: Double {
        processes.reduce(0) { $0 + $1.cpuPercent }
    }

    public var totalMemory: UInt64 {
        processes.reduce(0) { $0 + $1.memoryBytes }
    }

    public var totalMemoryFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalMemory), countStyle: .memory)
    }

    public var totalCPUFormatted: String {
        String(format: "%.1f%%", totalCPU)
    }

    public var processCount: Int {
        processes.count
    }

    public static func group(processes: [RunningProcess]) -> [ProcessGroup] {
        var groups: [String: [RunningProcess]] = [:]

        for process in processes {
            let key = groupKey(for: process)
            groups[key, default: []].append(process)
        }

        return groups.map { key, procs in
            let displayName = Self.extractDisplayName(from: procs)
            let icon = Self.extractIcon(from: procs)

            return ProcessGroup(
                id: key,
                displayName: displayName,
                icon: icon,
                processes: procs.sorted { $0.pid < $1.pid }
            )
        }
        .sorted { a, b in
            a.totalCPU > b.totalCPU
        }
    }

    private static func groupKey(for process: RunningProcess) -> String {
        if let bundleID = process.bundleID {
            return "bundle_\(bundleID)"
        }

        if let path = process.path {
            let url = URL(fileURLWithPath: path)
            let parentDir = url.deletingLastPathComponent().path

            if parentDir.contains("/Contents/MacOS") {
                let appPath = url.deletingLastPathComponent().deletingLastPathComponent().path
                return "path_\(appPath)"
            }

            if parentDir.hasSuffix("/bin") || parentDir.hasSuffix("/sbin") {
                let baseName = process.name.replacingOccurrences(of: "d$", with: "", options: .regularExpression)
                return "name_\(baseName)"
            }
        }

        let baseName = process.name
            .replacingOccurrences(of: "_helper$", with: "", options: .regularExpression)
            .replacingOccurrences(of: " Helper$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "Helper$", with: "", options: .regularExpression)
        return "name_\(baseName)"
    }

    private static func extractDisplayName(from processes: [RunningProcess]) -> String {
        if let mainProcess = processes.first(where: { $0.bundleID != nil }) {
            return mainProcess.name
        }

        if let first = processes.first {
            return first.name
        }

        return "Unknown"
    }

    private static func extractIcon(from processes: [RunningProcess]) -> String {
        if let mainProcess = processes.first(where: { $0.bundleID != nil }) {
            return mainProcess.bundleID ?? "app.fill"
        }

        return "app.fill"
    }
}
