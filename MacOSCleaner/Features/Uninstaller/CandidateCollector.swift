import Foundation

public actor CandidateCollector {
    private let fileManager: FileManager
    private let commandRunner: any CommandRunning

    public init(fileManager: FileManager = .default, commandRunner: any CommandRunning = CommandRunner()) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    public func collect(identity: AppIdentity, mode: ScanMode = .balanced) async -> Set<URL> {
        var candidates = Set<URL>()
        let home = NSHomeDirectory()
        let maxDepth = mode == .safe ? 3 : 5

        // 1. Fixed popular paths
        let basePaths = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Preferences",
            "\(home)/Library/Preferences/ByHost",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Logs",
            "\(home)/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Preferences",
            "/Library/Application Support",
            "\(home)/Library/Developer",
        ]

        for base in basePaths {
            let url = URL(fileURLWithPath: base)
            candidates.formUnion(await shallowScan(url, identity: identity, mode: mode))
        }

        // 2. Deep scan critical folders
        let deepFolders = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Preferences",
            "\(home)/Library/Application Scripts",
        ]
        for dir in deepFolders {
            let url = URL(fileURLWithPath: dir)
            candidates.formUnion(await deepScan(url, identity: identity, depth: 0, maxDepth: maxDepth))
        }

        // 3. pkgutil receipts
        if identity.bundleID.count > 0 {
            if let result = try? await commandRunner.run(command: "/usr/sbin/pkgutil", arguments: ["--files", identity.bundleID]) {
                for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
                    let path = "/\(line)"
                    if fileManager.fileExists(atPath: path) {
                        candidates.insert(URL(fileURLWithPath: path))
                    }
                }
            }
        }

        // 4. mdfind (balanced only)
        if mode == .balanced {
            let mdfindCandidates = await runMdfind(identity: identity)
            candidates.formUnion(mdfindCandidates)
        }

        // 5. App-specific Electron paths
        if identity.isElectron {
            let electronPath = "\(home)/Library/Application Support/\(identity.appName)"
            if fileManager.fileExists(atPath: electronPath) {
                candidates.insert(URL(fileURLWithPath: electronPath))
            }
        }

        // 6. JetBrains-specific (balanced only)
        if mode == .balanced, identity.isJetBrains {
            let jbPath = "\(home)/Library/Application Support/JetBrains"
            if fileManager.fileExists(atPath: jbPath) {
                candidates.formUnion(await shallowScan(URL(fileURLWithPath: jbPath), identity: identity, mode: mode))
                candidates.formUnion(await deepScan(URL(fileURLWithPath: jbPath), identity: identity, depth: 0, maxDepth: maxDepth))
            }
        }

        // 7. Docker-specific
        if identity.isDocker {
            let dockerPaths = [
                "\(home)/Library/Containers/com.docker.docker",
                "\(home)/Library/Group Containers/group.com.docker",
            ]
            for p in dockerPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 8. Adobe-specific
        let adobeVendor = identity.appName.lowercased().hasPrefix("adobe") ||
            identity.bundleID.lowercased().hasPrefix("com.adobe.")
        if adobeVendor {
            let adobePaths = [
                "\(home)/Library/Application Support/Adobe",
                "/Library/Application Support/Adobe",
                "\(home)/Library/Preferences/Adobe",
                "/Library/Preferences/Adobe",
                "\(home)/.adobe",
                "\(home)/Creative Cloud Files",
            ]
            for p in adobePaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 9. Microsoft Office-specific
        let msVendor = identity.appName.lowercased().hasPrefix("microsoft") ||
            identity.bundleID.lowercased().hasPrefix("com.microsoft.")
        if msVendor {
            let msPaths = [
                "\(home)/Library/Application Support/Microsoft",
                "\(home)/Library/Application Support/Microsoft Office",
                "\(home)/Library/Group Containers/UBF8T346G9.Office",
                "\(home)/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite",
                "/Library/Application Support/Microsoft",
                "\(home)/Library/Containers/com.microsoft.word",
                "\(home)/Library/Containers/com.microsoft.excel",
                "\(home)/Library/Containers/com.microsoft.powerpoint",
                "\(home)/Library/Containers/com.microsoft.outlook",
                "\(home)/Library/Containers/com.microsoft.teams",
            ]
            for p in msPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 10. Steam-specific
        if identity.bundleID == "com.valvesoftware.steam" || identity.appName == "Steam" {
            let steamPaths = [
                "\(home)/Library/Application Support/Steam",
            ]
            for p in steamPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 11. Epic Games-specific
        if identity.bundleID == "com.epicgames.EpicGamesLauncher" || identity.appName.lowercased().contains("epic") {
            let epicPaths = [
                "\(home)/Library/Application Support/Epic",
                "\(home)/Library/Application Support/Epic Games Launcher",
            ]
            for p in epicPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 12. Unity-specific
        if identity.bundleID.lowercased().hasPrefix("com.unity3d.") || identity.appName == "Unity Hub" {
            let unityPaths = [
                "\(home)/Library/Application Support/Unity",
                "\(home)/Library/Application Support/Unity Hub",
                "\(home)/.local/share/unity3d",
            ]
            for p in unityPaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        // 13. Network extension / VPN-specific
        let isNetworkExt = identity.bundleID.lowercased().contains("littlesnitch") ||
            identity.bundleID.lowercased().contains("nordvpn") ||
            identity.bundleID.lowercased().contains("expressvpn") ||
            identity.appName.lowercased().contains("vpn") ||
            identity.appName.lowercased().contains("snitch")
        if isNetworkExt {
            let nePaths = [
                "/Library/SystemExtensions",
                "/Library/StagedExtensions",
                "\(home)/Library/Application Support/Little Snitch",
                "\(home)/Library/Application Support/NordVPN",
            ]
            for p in nePaths where fileManager.fileExists(atPath: p) {
                candidates.insert(URL(fileURLWithPath: p))
            }
        }

        return candidates
    }

    private func shallowScan(_ url: URL, identity: AppIdentity, mode: ScanMode = .balanced) async -> Set<URL> {
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            if matchCandidate(item, identity: identity, mode: mode) {
                found.insert(item)
            }
        }
        return found
    }

    private func deepScan(_ url: URL, identity: AppIdentity, depth: Int, maxDepth: Int) async -> Set<URL> {
        guard depth <= maxDepth else { return [] }
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            if matchCandidate(item, identity: identity, mode: .balanced) {
                found.insert(item)
            }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let sub = await deepScan(item, identity: identity, depth: depth + 1, maxDepth: maxDepth)
                found.formUnion(sub)
            }
        }
        return found
    }

    private func matchCandidate(_ url: URL, identity: AppIdentity, mode: ScanMode = .balanced) -> Bool {
        let name = url.lastPathComponent
        let lowerName = name.lowercased()

        // Exact matches — always checked
        if name == identity.bundleID || name.hasPrefix(identity.bundleID + ".") {
            return true
        }
        if name == identity.appName || name.hasPrefix(identity.appName + " ") || name.hasPrefix(identity.appName + ".") {
            return true
        }

        // Safe mode: only exact matches above
        if mode == .safe { return false }

        // Balanced: vendor, contains, executable matching
        if identity.vendorNames.contains(name) {
            return true
        }
        if identity.vendorNames.contains(where: { lowerName.contains($0.lowercased()) }) {
            return true
        }
        if lowerName.contains(identity.bundleID.lowercased()) {
            return true
        }
        if lowerName.contains(identity.appName.lowercased()) {
            return true
        }
        if lowerName == identity.executableName.lowercased() {
            return true
        }

        return false
    }

    private func runMdfind(identity: AppIdentity) async -> Set<URL> {
        var urls = Set<URL>()
        let queries = [identity.bundleID, identity.appName, identity.executableName]
        for query in queries {
            guard !query.isEmpty else { continue }
            if let result = try? await commandRunner.run(command: "/usr/bin/mdfind", arguments: [query]) {
                for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
                    let url = URL(fileURLWithPath: line)
                    urls.insert(url)
                }
            }
        }
        return urls
    }
}
