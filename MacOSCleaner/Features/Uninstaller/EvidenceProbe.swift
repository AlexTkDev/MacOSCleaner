import Foundation

public actor EvidenceProbe {
    private let commandRunner: any CommandRunning
    private let codesignCache: CodesignCache
    private let plistCache: PlistContentCache

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        codesignCache: CodesignCache = CodesignCache(),
        plistCache: PlistContentCache = PlistContentCache()
    ) {
        self.commandRunner = commandRunner
        self.codesignCache = codesignCache
        self.plistCache = plistCache
    }

    public func probe(url: URL, identity: AppIdentity) async -> Set<Evidence> {
        var evidence = Set<Evidence>()

        let fileName = url.lastPathComponent
        let parentFolder = url.deletingLastPathComponent().lastPathComponent
        let path = url.path.lowercased()

        // Identity checks
        if fileName == identity.bundleID {
            evidence.insert(.bundleIDExact)
        } else if fileName.hasPrefix(identity.bundleID + ".") || fileName == identity.bundleID {
            evidence.insert(.bundleIDPrefix)
        }

        if fileName == identity.appName {
            evidence.insert(.appNameExact)
        } else if fileName.hasPrefix(identity.appName + " ") || fileName.hasPrefix(identity.appName + "-") {
            evidence.insert(.appNamePrefix)
        }

        if identity.vendorNames.contains(fileName) || identity.vendorNames.contains(parentFolder) {
            evidence.insert(.vendorName)
        }

        if identity.frameworkNames.contains(fileName) || identity.frameworkNames.contains(fileName.replacingOccurrences(of: ".framework", with: "")) {
            evidence.insert(.frameworkName)
        }

        if identity.xpcServiceNames.contains(fileName) || identity.xpcServiceNames.contains(fileName.replacingOccurrences(of: ".xpc", with: "")) {
            evidence.insert(.xpcServiceName)
        }

        if identity.plugInNames.contains(fileName) || identity.plugInNames.contains(fileName.replacingOccurrences(of: ".bundle", with: "")) {
            evidence.insert(.plugInName)
        }

        if fileName == identity.executableName {
            evidence.insert(.executableName)
        }

        // Container checks
        if parentFolder == "Containers" && fileName == identity.bundleID {
            evidence.insert(.container)
        }
        if parentFolder == "Group Containers" && (fileName == "group.\(identity.bundleID)" || fileName.hasPrefix("group.\(identity.bundleID).")) {
            evidence.insert(.appGroup)
        }

        // System integration
        if path.contains("/launchagents/") && (path.contains(identity.bundleID.lowercased()) || fileName.lowercased().contains(identity.appName.lowercased())) {
            evidence.insert(.launchAgent)
        }
        if path.contains("/launchdaemons/") && (path.contains(identity.bundleID.lowercased()) || fileName.lowercased().contains(identity.appName.lowercased())) {
            evidence.insert(.launchDaemon)
        }

        // Application Scripts
        if path.contains("/application scripts/\(identity.bundleID.lowercased())") {
            evidence.insert(.extension)
        }

        // Electron cache detection
        if identity.isElectron {
            let electronDirs = ["Cache", "Code Cache", "GPUCache", "Local Storage", "Session Storage", "IndexedDB", "Network"]
            if electronDirs.contains(fileName) && path.contains("/application support/\(identity.appName.lowercased())") {
                evidence.insert(.electronCache)
            }
        }

        // JetBrains config
        if identity.isJetBrains && path.contains("/application support/jetbrains") {
            evidence.insert(.jetBrainsConfig)
        }

        // Flutter build
        if identity.isFlutter && (path.contains(".dart_tool") || path.contains("/build/flutter")) {
            evidence.insert(.flutterBuild)
        }

        // Code signature probe
        let binaryExts: Set<String> = ["", "app", "bundle", "kext", "framework", "dylib", "xpc"]
        let fileExt = url.pathExtension
        if binaryExts.contains(fileExt) || fileExt.isEmpty {
            if let candidateTeamID = await codesignCache.getTeamID(url: url, commandRunner: commandRunner) {
                if candidateTeamID == identity.teamID && identity.teamID != nil {
                    evidence.insert(.teamID)
                }
            }
            if let auth = identity.signingAuthority {
                let result = try? await commandRunner.run(command: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", url.path])
                if let output = result?.stderr, output.contains(auth) {
                    evidence.insert(.developerSignature)
                }
            }
        }

        // Plist content probe
        if url.pathExtension == "plist" || fileName.hasSuffix(".plist") {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size > 0 && size < 512 * 1024 {
                if let content = await plistCache.getContent(url: url) {
                    let lower = content.lowercased()
                    if lower.contains(identity.bundleID.lowercased()) || lower.contains(identity.appName.lowercased()) {
                        evidence.insert(.plistContent)
                    }
                }
            }
        }

        return evidence
    }
}
