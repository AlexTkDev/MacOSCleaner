import Foundation
import OSLog

private extension Logger {
    static let updater = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "UpdateChecker")
}

public struct AvailableUpdate: Sendable, Equatable {
    public let version: String
    public let dmgURL: URL?

    public var openURL: URL {
        dmgURL ?? UpdateChecker.releasesURL
    }
}

public actor UpdateChecker {
    public static let releasesURL = URL(string: "https://github.com/AlexTkDev/MacOSCleaner/releases")!
    private static let apiURL = URL(string: "https://api.github.com/repos/AlexTkDev/MacOSCleaner/releases/latest")!

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    public func checkForUpdate() async -> AvailableUpdate? {
        guard let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        do {
            var request = URLRequest(url: Self.apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let remoteTag = release.tag_name
            let remoteVersion = remoteTag.hasPrefix("v") ? String(remoteTag.dropFirst()) : remoteTag
            guard isNewer(remoteVersion, than: localVersion) else { return nil }

            let dmgURL = release.assets
                .first { $0.name.lowercased().hasSuffix(".dmg") }
                .flatMap { URL(string: $0.browser_download_url) }

            Logger.updater.info("Update available: \(remoteVersion, privacy: .public) (current: \(localVersion, privacy: .public))")
            return AvailableUpdate(version: remoteVersion, dmgURL: dmgURL)
        } catch {
            Logger.updater.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = versionComponents(remote)
        let l = versionComponents(local)
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
}
