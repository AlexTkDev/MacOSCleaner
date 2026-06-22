import Foundation
import OSLog

private extension Logger {
    static let scanActor = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "ScanActor")
}

public actor ScanActor {
    private let fm = FileManager.default
    private let sizeCache: DirectorySizeCache

    public init(sizeCache: DirectorySizeCache = DirectorySizeCache()) {
        self.sizeCache = sizeCache
    }

    func collectInstalledApps() -> Set<String> {
        var apps = Set<String>()
        let searchPaths = ["/Applications", "\(fm.homeDirectoryForCurrentUser.path)/Applications", "/Applications/Setapp"]
        for basePath in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let appPath = "\(basePath)/\(item)"
                if let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
                   let bundleID = bundle.bundleIdentifier {
                    apps.insert(bundleID.lowercased())
                    let parts = bundleID.components(separatedBy: ".")
                    if let last = parts.last { apps.insert(last.lowercased()) }
                }
                let appName = item.replacingOccurrences(of: ".app", with: "").lowercased()
                apps.insert(appName)
            }
        }
        return apps
    }

    func isEntryInstalled(_ entry: String, installedApps: Set<String>, processActor: ProcessCleanupActor? = nil) async -> Bool {
        let lower = entry.lowercased()
        if installedApps.contains(lower) { return true }
        for part in lower.components(separatedBy: ".") where part.count >= 3 {
            if installedApps.contains(part) { return true }
        }
        for app in installedApps where app.count >= 3 {
            if lower.contains(app) || app.contains(lower) { return true }
        }
        if lower.contains("microsoft") || lower.contains("office") {
            if installedApps.contains(where: { $0.contains("microsoft") || $0.contains("office") }) { return true }
        }
        if lower.contains("adobe") {
            if installedApps.contains(where: { $0.contains("adobe") }) { return true }
        }
        if lower.contains("google") {
            if installedApps.contains(where: { $0.contains("google") }) { return true }
        }
        if lower.contains("homebrew") {
            if let actor = processActor, await actor.commandExists("brew") { return true }
        }
        return false
    }

    func scanDirectoryEntries(_ path: String) -> [String] {
        (try? fm.contentsOfDirectory(atPath: path)) ?? []
    }

    func getDirectorySize(_ path: String) -> Int64 {
        fm.getDirectorySize(url: URL(fileURLWithPath: path))
    }
}
