import Foundation

public struct RunningProcess: Identifiable, Sendable, Hashable {
    public let id: pid_t
    public let pid: pid_t
    public let name: String
    public let path: String?
    public let user: String?

    public init(pid: pid_t, name: String, path: String? = nil, user: String? = nil) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.path = path
        self.user = user
    }

    public var isUserProcess: Bool {
        guard let user else { return false }
        let currentUser = ProcessInfo.processInfo.environment["USER"]
            ?? String(cString: getenv("USER"))
        return user == currentUser
    }

    public static func == (lhs: RunningProcess, rhs: RunningProcess) -> Bool {
        lhs.pid == rhs.pid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}
