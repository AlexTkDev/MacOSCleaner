import Foundation

public actor CandidateCollector {
    private let fileManager: FileManager
    private let commandRunner: any CommandRunning

    public init(fileManager: FileManager = .default, commandRunner: any CommandRunning = CommandRunner()) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    public func collect(identity: AppIdentity) async -> Set<URL> {
        var candidates = Set<URL>()
        let home = NSHomeDirectory()

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
            candidates.formUnion(await shallowScan(url, identity: identity))
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
            candidates.formUnion(await deepScan(url, identity: identity, depth: 0, maxDepth: 5))
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

        // 4. mdfind
        let mdfindCandidates = await runMdfind(identity: identity)
        candidates.formUnion(mdfindCandidates)

        // 5. App-specific Electron paths
        if identity.isElectron {
            let electronPath = "\(home)/Library/Application Support/\(identity.appName)"
            if fileManager.fileExists(atPath: electronPath) {
                candidates.insert(URL(fileURLWithPath: electronPath))
            }
        }

        // 6. JetBrains-specific
        if identity.isJetBrains {
            let jbPath = "\(home)/Library/Application Support/JetBrains"
            if fileManager.fileExists(atPath: jbPath) {
                candidates.formUnion(await shallowScan(URL(fileURLWithPath: jbPath), identity: identity))
                candidates.formUnion(await deepScan(URL(fileURLWithPath: jbPath), identity: identity, depth: 0, maxDepth: 4))
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

        return candidates
    }

    private func shallowScan(_ url: URL, identity: AppIdentity) async -> Set<URL> {
        var found = Set<URL>()
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return found
        }
        for item in contents {
            if matchCandidate(item, identity: identity) {
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
            if matchCandidate(item, identity: identity) {
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

    private func matchCandidate(_ url: URL, identity: AppIdentity) -> Bool {
        let name = url.lastPathComponent
        let lowerName = name.lowercased()

        if name == identity.bundleID || name.hasPrefix(identity.bundleID + ".") {
            return true
        }
        if name == identity.appName || name.hasPrefix(identity.appName + " ") || name.hasPrefix(identity.appName + ".") {
            return true
        }
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
