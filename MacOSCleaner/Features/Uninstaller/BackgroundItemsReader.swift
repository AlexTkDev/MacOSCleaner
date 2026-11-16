import AppKit
import Foundation

public enum BackgroundItemsAccessStatus: Sendable, Equatable {
    case available
    case authorizationRequired
    case unavailable
}

public struct BackgroundItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let identifier: String
    public let developerName: String?
    public let teamID: String?
    public let type: String
    public let url: URL?
    public let executablePath: String?
    public let isEnabled: Bool
}

public struct LoginItemsSnapshot: Sendable, Equatable {
    public let items: [BackgroundItem]
    public let accessStatus: BackgroundItemsAccessStatus
}

public actor BackgroundItemsReader {
    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func readLaunchAgents() async -> Set<URL> {
        let paths = [
            NormalizedPath.joinHome(NSHomeDirectory(), "Library/LaunchAgents"),
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]
        var urls = Set<URL>()
        for path in paths {
            let dir = NormalizedPath.url(path, isDirectory: true)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for url in contents where url.pathExtension == "plist" {
                urls.insert(NormalizedPath.canonicalize(url))
            }
        }
        return NormalizedPath.urls(urls)
    }

    public func readLoginItems() async -> Set<URL> {
        let snapshot = await readLoginItemEntries()
        var urls = Set<URL>()
        for item in snapshot.items {
            if let url = item.url {
                urls.insert(NormalizedPath.canonicalize(url))
            }
            if let execPath = item.executablePath, execPath.hasPrefix("/") {
                urls.insert(NormalizedPath.url(execPath))
            }
        }
        return NormalizedPath.urls(urls)
    }

    public func readLoginItemEntries() async -> LoginItemsSnapshot {
        guard let result = try? await commandRunner.run(
            command: "/usr/bin/sfltool",
            arguments: ["dumpbtm"]
        ) else {
            return LoginItemsSnapshot(items: [], accessStatus: .unavailable)
        }

        let combinedErrors = (result.stderr + "\n" + result.stdout).lowercased()
        if result.exitCode != 0 {
            if combinedErrors.contains("authorization")
                || combinedErrors.contains("system.privilege.admin")
                || combinedErrors.contains("-60002") {
                return LoginItemsSnapshot(items: [], accessStatus: .authorizationRequired)
            }
            return LoginItemsSnapshot(items: [], accessStatus: .unavailable)
        }

        let items = Self.parseDumpBTMOutput(result.stdout)
        return LoginItemsSnapshot(items: items, accessStatus: .available)
    }

    /// Parses `sfltool dumpbtm` text blocks and returns Login Item / App entries (LaunchAgents/Daemons are scanned directly from disk).
    static func parseDumpBTMOutput(_ output: String) -> [BackgroundItem] {
        var blocks: [[String: String]] = []
        var current: [String: String] = [:]

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || (line.hasPrefix("#") && line.hasSuffix(":")) || line.hasPrefix("====") {
                if !current.isEmpty {
                    blocks.append(current)
                    current = [:]
                }
                continue
            }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty {
                current[key] = value
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }

        var parentURLByIdentifier: [String: URL] = [:]
        for block in blocks {
            guard let id = block["Identifier"],
                  let rawURL = block["URL"],
                  let url = URL(string: rawURL),
                  url.isFileURL else { continue }
            let canonical = NormalizedPath.canonicalize(url)
            parentURLByIdentifier[id] = canonical
            let stripped = LaunchServiceManager.stripBTMPrefix(from: id)
            parentURLByIdentifier[stripped] = canonical
        }

        var items: [BackgroundItem] = []
        var seenIDs = Set<String>()

        for block in blocks {
            let rawType = (block["Type"] ?? "").lowercased()
            // Keep login items & login apps; skip agents/daemons already covered by LaunchServiceManager plist scan.
            guard rawType.contains("login item") || rawType.hasPrefix("app") else { continue }

            let name = block["Name"] ?? block["Identifier"] ?? ""
            let identifier = block["Identifier"] ?? name
            guard !identifier.isEmpty else { continue }

            let rawURL = block["URL"]
            var parsedURL: URL? = rawURL.flatMap { raw in
                guard let url = URL(string: raw), url.isFileURL else { return nil }
                return NormalizedPath.canonicalize(url)
            }
            var execPath = block["Executable Path"]

            if parsedURL == nil {
                let strippedID = LaunchServiceManager.stripBTMPrefix(from: identifier)
                let parentID = block["Parent Identifier"] ?? ""
                let parentAppURL = parentURLByIdentifier[parentID]
                    ?? parentURLByIdentifier[LaunchServiceManager.stripBTMPrefix(from: parentID)]
                parsedURL = resolveHelperBundleURL(
                    bundleID: strippedID,
                    itemName: name,
                    parentAppURL: parentAppURL
                )
            }
            if execPath == nil, let bundleURL = parsedURL {
                execPath = Bundle(url: bundleURL)?.executableURL?.path
            }

            let uniqueKey = "\(identifier)|\(parsedURL?.path ?? execPath ?? "")"
            guard seenIDs.insert(uniqueKey).inserted else { continue }

            let disposition = (block["Disposition"] ?? "").lowercased()
            let isEnabled = disposition.contains("enabled") && !disposition.contains("disabled")

            items.append(BackgroundItem(
                id: uniqueKey,
                name: name.isEmpty ? identifier : name,
                identifier: identifier,
                developerName: block["Developer Name"],
                teamID: block["Team Identifier"],
                type: block["Type"] ?? "login item",
                url: parsedURL,
                executablePath: execPath,
                isEnabled: isEnabled
            ))
        }

        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func resolveHelperBundleURL(
        bundleID: String,
        itemName: String,
        parentAppURL: URL?
    ) -> URL? {
        if let parentAppURL {
            let loginItemsDir = parentAppURL.appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
            if let children = try? FileManager.default.contentsOfDirectory(
                at: loginItemsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for child in children where child.pathExtension.lowercased() == "app" {
                    let childBundleID = Bundle(url: child)?.bundleIdentifier
                    if let childBundleID, childBundleID.caseInsensitiveCompare(bundleID) == .orderedSame {
                        return NormalizedPath.canonicalize(child)
                    }
                    if !itemName.isEmpty,
                       child.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(itemName) == .orderedSame {
                        return NormalizedPath.canonicalize(child)
                    }
                }
            }
        }
        return nil
    }
}
