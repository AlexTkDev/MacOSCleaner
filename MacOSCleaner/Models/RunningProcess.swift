import Foundation

public struct RunningProcess: Identifiable, Sendable, Hashable {
    public let id: pid_t
    public let pid: pid_t
    public let name: String
    public let path: String?
    public let user: String?

    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let threadCount: Int
    public let startTime: Date?
    public let parentPID: pid_t
    public let bundleID: String?

    public init(
        pid: pid_t,
        name: String,
        path: String? = nil,
        user: String? = nil,
        cpuPercent: Double = 0,
        memoryBytes: UInt64 = 0,
        threadCount: Int = 0,
        startTime: Date? = nil,
        parentPID: pid_t = 0,
        bundleID: String? = nil
    ) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.path = path
        self.user = user
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threadCount = threadCount
        self.startTime = startTime
        self.parentPID = parentPID
        self.bundleID = bundleID
    }

    public var isUserProcess: Bool {
        guard let user else { return false }
        let currentUser = ProcessInfo.processInfo.environment["USER"]
            ?? String(cString: getenv("USER"))
        return user == currentUser
    }

    public var memoryFormatted: String {
        ByteCountFormatter.localizedString(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    public var cpuFormatted: String {
        String(format: "process_cpu_format".localized, cpuPercent)
    }

    public var uptime: TimeInterval? {
        guard let startTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }

    public var uptimeFormatted: String? {
        guard let uptime else { return nil }
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        if hours > 0 {
            return String(format: "process_uptime_hours_format".localized, hours, minutes)
        }
        return String(format: "process_uptime_minutes_format".localized, minutes)
    }

    public static func == (lhs: RunningProcess, rhs: RunningProcess) -> Bool {
        lhs.pid == rhs.pid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}
