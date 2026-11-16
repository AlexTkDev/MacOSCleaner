import AppKit
import Foundation

public enum LaunchServiceError: Error {
    case toggleFailed(String)
}

public actor LaunchServiceManager {
    private let commandRunner: any CommandRunning
    private let fileManager: FileManager
    private let trashManager: TrashManager
    private let backgroundItemsReader: BackgroundItemsReader
    private let signatureChecker: @Sendable (String) async -> CodeSignatureInfo
    private let searchPaths: [String]

    private static let vendorPrefixesKey = "startupSystemVendorPrefixes"
    private static let disabledLoginItemsKey = "startupDisabledLoginItems"
    private static let defaultVendorPrefixes = ["com.apple."]
    private static let maxConcurrentSignatureChecks = 6

    private var disabledLoginItemIDs: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: Self.disabledLoginItemsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.disabledLoginItemsKey)
        }
    }

    public var systemVendorPrefixes: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: Self.vendorPrefixesKey) ?? Self.defaultVendorPrefixes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.vendorPrefixesKey)
        }
    }

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        fileManager: FileManager = .default,
        searchPaths: [String]? = nil,
        trashManager: TrashManager? = nil,
        backgroundItemsReader: BackgroundItemsReader = BackgroundItemsReader(),
        signatureChecker: (@Sendable (String) async -> CodeSignatureInfo)? = nil
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.trashManager = trashManager ?? TrashManager()
        self.backgroundItemsReader = backgroundItemsReader
        self.signatureChecker = signatureChecker ?? { path in
            await CodeSignatureInfo.check(path: path)
        }

        if let searchPaths = searchPaths {
            self.searchPaths = searchPaths
        } else {
            let home = NSHomeDirectory()
            self.searchPaths = [
                "\(home)/Library/LaunchAgents",
                "/Library/LaunchAgents",
                "/Library/LaunchDaemons"
            ]
        }
    }

    public func scan() async throws -> [StartupService] {
        var allServices: [StartupService] = []
        let loadedLabels = try await getLoadedLabels()
        let prefixes = systemVendorPrefixes

        for path in searchPaths {
            let url = URL(fileURLWithPath: path)

            // Scan is read-only. Do not run deletion validate() on these roots —
            // SafetyManager exact-refuses LaunchAgents/LaunchDaemons directories themselves.
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            let fileURLs = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []

            let plists = fileURLs.filter { $0.pathExtension == "plist" }

            for plistURL in plists {
                if let metadata = extractPlistMetadata(from: plistURL) {
                    let isEnabled = loadedLabels.contains(metadata.label)
                    let category = categorize(path: plistURL.path, label: metadata.label, prefixes: prefixes)
                    let execPath = metadata.executablePath
                    let exists = execPath.map { path in
                        path.hasPrefix("/") ? fileManager.fileExists(atPath: path) : true
                    } ?? true
                    let location = ExecutableLocation.classify(path: execPath)

                    allServices.append(StartupService(
                        id: metadata.label,
                        name: metadata.label,
                        path: plistURL.path,
                        isEnabled: isEnabled,
                        category: category,
                        executablePath: execPath,
                        executableExists: exists,
                        executableLocation: location
                    ))
                }
            }
        }

        var uniqueServices: [String: StartupService] = [:]
        for service in allServices where uniqueServices[service.id] == nil {
            uniqueServices[service.id] = service
        }

        let sorted = Array(uniqueServices.values).sorted { $0.name < $1.name }
        return await enrichSignatures(for: sorted)
    }

    public func scanAll() async throws -> (
        services: [StartupService],
        loginItems: [StartupService],
        loginItemsAccess: BackgroundItemsAccessStatus
    ) {
        async let servicesTask = scan()
        async let btmTask = backgroundItemsReader.readLoginItemEntries()
        async let disabledLabelsTask = getDisabledLabels()

        let services = try await servicesTask
        let snapshot = await btmTask
        let launchdDisabled = await disabledLabelsTask
        let locallyDisabled = disabledLoginItemIDs

        let rawLoginItems = snapshot.items.map { item -> StartupService in
            let targetPath = item.executablePath ?? item.url?.path
            let displayPath = item.url?.path ?? item.executablePath ?? item.identifier
            let exists = targetPath.map { fileManager.fileExists(atPath: $0) } ?? true
            let strippedID = Self.stripBTMPrefix(from: item.identifier)
            let isOverriddenDisabled = launchdDisabled.contains(item.identifier)
                || launchdDisabled.contains(strippedID)
                || locallyDisabled.contains(item.identifier)
                || locallyDisabled.contains(strippedID)
            return StartupService(
                id: item.id,
                name: item.name,
                path: displayPath,
                isEnabled: item.isEnabled && !isOverriddenDisabled,
                category: .user,
                executablePath: targetPath,
                executableExists: exists,
                executableLocation: ExecutableLocation.classify(path: targetPath),
                isLoginItem: true,
                developerName: item.developerName
            )
        }
        let enrichedLoginItems = await enrichSignatures(for: rawLoginItems)
        return (services, enrichedLoginItems, snapshot.accessStatus)
    }

    private func enrichSignatures(for services: [StartupService]) async -> [StartupService] {
        let pathsToCheck = Array(Set(services.compactMap { service -> String? in
            guard service.executableExists, let path = service.executablePath, path.hasPrefix("/") else {
                return nil
            }
            return path
        }))
        guard !pathsToCheck.isEmpty else { return services }

        let checker = signatureChecker
        var signaturesByPath: [String: CodeSignatureInfo] = [:]

        await withTaskGroup(of: (String, CodeSignatureInfo).self) { group in
            var pending = pathsToCheck[...]
            for path in pending.prefix(Self.maxConcurrentSignatureChecks) {
                group.addTask { (path, await checker(path)) }
            }
            pending = pending.dropFirst(min(Self.maxConcurrentSignatureChecks, pending.count))

            for await (path, sig) in group {
                signaturesByPath[path] = sig
                if let next = pending.first {
                    pending = pending.dropFirst()
                    group.addTask { (next, await checker(next)) }
                }
            }
        }

        return services.map { service in
            guard let execPath = service.executablePath,
                  let signature = signaturesByPath[execPath] else {
                return service
            }
            return StartupService(
                id: service.id,
                name: service.name,
                path: service.path,
                isEnabled: service.isEnabled,
                category: service.category,
                executablePath: service.executablePath,
                executableExists: service.executableExists,
                executableLocation: service.executableLocation,
                signature: signature,
                isLoginItem: service.isLoginItem,
                developerName: service.developerName
            )
        }
    }

    private func getLoadedLabels() async throws -> Set<String> {
        var labels = Set<String>()

        let userResult = try await commandRunner.run(command: "/bin/launchctl", arguments: ["list"])
        if userResult.exitCode == 0 {
            let lines = userResult.stdout.components(separatedBy: .newlines)
            for line in lines.dropFirst() {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3 {
                    labels.insert(parts[2])
                }
            }
        }

        // Also query via print gui/<uid> for more complete user agent list
        let uid = getuid()
        let guiResult = try await commandRunner.run(command: "/bin/launchctl", arguments: ["print", "gui/\(uid)"])
        if guiResult.exitCode == 0 {
            labels.formUnion(parseSystemLabels(from: guiResult.stdout))
        }

        let systemResult = try await commandRunner.run(command: "/bin/launchctl", arguments: ["print", "system"])
        if systemResult.exitCode == 0 {
            labels.formUnion(parseSystemLabels(from: systemResult.stdout))
        }

        return labels
    }

    private func parseSystemLabels(from output: String) -> Set<String> {
        var labels = Set<String>()
        var inServicesSection = false

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "services = {" {
                inServicesSection = true
                continue
            }
            if inServicesSection && trimmed == "}" {
                inServicesSection = false
                continue
            }

            if inServicesSection {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3 {
                    labels.insert(parts[2])
                }
            }
        }
        return labels
    }

    public nonisolated func categorize(path: String, label: String, prefixes: [String], homeDirectory: String = NSHomeDirectory()) -> ServiceCategory {
        if prefixes.contains(where: label.hasPrefix) {
            return .system
        }
        if path.hasPrefix("\(homeDirectory)/Library/") {
            return .user
        }
        return .thirdParty
    }

    private func extractPlistMetadata(from url: URL) -> (label: String, executablePath: String?)? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let label = plist["Label"] as? String else {
            return nil
        }
        let program = plist["Program"] as? String
        let firstArg = (plist["ProgramArguments"] as? [String])?.first
        let rawExec = (program?.isEmpty == false ? program : firstArg)
        let executablePath = rawExec?.isEmpty == false ? rawExec : nil
        return (label, executablePath)
    }

    public func disable(service: StartupService) async throws {
        guard service.category != .system, !service.requiresRoot else {
            throw LaunchServiceError.toggleFailed("System services require administrator privileges")
        }

        let uid = getuid()
        let domain = "gui/\(uid)"
        if service.isLoginItem {
            let (rawID, bundleID) = Self.loginItemIdentifiers(for: service)
            let loaded = (try? await getLoadedLabels()) ?? []
            var candidates: [String] = []
            for id in [bundleID, rawID] where !id.isEmpty && !candidates.contains(id) {
                candidates.append(id)
            }
            for label in loaded where !bundleID.isEmpty {
                if (label == bundleID || label.hasPrefix("application.\(bundleID).")) && !candidates.contains(label) {
                    candidates.append(label)
                }
            }

            // 1. Disable in both gui/<uid> and user/<uid> first so launchd neither respawns
            //    the monitor now nor launches it after reboot (persisted in disabled.<uid>.plist).
            for targetDomain in [domain, "user/\(uid)"] {
                for label in candidates {
                    let target = "\(targetDomain)/\(label)"
                    _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["disable", target])
                }
            }

            // 2. Kill with SIGKILL and bootout from launchd.
            for targetDomain in [domain, "user/\(uid)"] {
                for label in candidates {
                    let target = "\(targetDomain)/\(label)"
                    _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["kill", "SIGKILL", target])
                    _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["bootout", target])
                }
            }

            // 3. Force-kill any running process matching bundleID, helper path, executable, or name.
            await terminateRunningLoginItem(
                bundleID: bundleID,
                name: service.name,
                path: service.path,
                executablePath: service.executablePath
            )

            var updated = disabledLoginItemIDs
            if !bundleID.isEmpty { updated.insert(bundleID) }
            if !rawID.isEmpty { updated.insert(rawID) }
            disabledLoginItemIDs = updated
            return
        }

        let target = "\(domain)/\(service.id)"
        _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["disable", target])
        let result = try await commandRunner.run(command: "/bin/launchctl", arguments: ["bootout", target])

        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("no such process") || stderr.contains("could not find service") {
                return
            }
            throw LaunchServiceError.toggleFailed(result.stderr)
        }
    }

    public func enable(service: StartupService) async throws {
        guard service.category != .system, !service.requiresRoot else {
            throw LaunchServiceError.toggleFailed("System services require administrator privileges")
        }

        let uid = getuid()
        let domain = "gui/\(uid)"
        if service.isLoginItem {
            let (rawID, bundleID) = Self.loginItemIdentifiers(for: service)
            var candidates = [bundleID]
            if rawID != bundleID && !rawID.isEmpty {
                candidates.append(rawID)
            }
            for targetDomain in [domain, "user/\(uid)"] {
                for label in candidates where !label.isEmpty {
                    let target = "\(targetDomain)/\(label)"
                    _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["enable", target])
                    _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["kickstart", target])
                }
            }
            var updated = disabledLoginItemIDs
            updated.remove(bundleID)
            updated.remove(rawID)
            disabledLoginItemIDs = updated
            return
        }

        let target = "\(domain)/\(service.id)"
        _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["enable", target])
        let result = try await commandRunner.run(
            command: "/bin/launchctl",
            arguments: ["bootstrap", domain, service.path]
        )

        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("already loaded") || result.exitCode == 37 {
                return
            }
            throw LaunchServiceError.toggleFailed(result.stderr)
        }
    }

    public nonisolated static func stripBTMPrefix(from identifier: String) -> String {
        guard let dotIndex = identifier.firstIndex(of: ".") else { return identifier }
        let prefix = identifier[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return identifier }
        return String(identifier[identifier.index(after: dotIndex)...])
    }

    public nonisolated static func loginItemIdentifiers(for service: StartupService) -> (rawIdentifier: String, bundleID: String) {
        let raw = service.id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? service.id
        let effectiveRaw = raw.isEmpty ? service.path : raw
        let stripped = stripBTMPrefix(from: effectiveRaw)
        return (effectiveRaw, stripped)
    }

    private func getDisabledLabels() async -> Set<String> {
        let uid = getuid()
        guard let result = try? await commandRunner.run(
            command: "/bin/launchctl",
            arguments: ["print-disabled", "gui/\(uid)"]
        ), result.exitCode == 0 else {
            return []
        }
        return Self.parseDisabledLabels(from: result.stdout)
    }

    nonisolated static func parseDisabledLabels(from output: String) -> Set<String> {
        var disabled = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""),
                  let arrowRange = trimmed.range(of: "\" => ") else { continue }
            let label = String(trimmed[trimmed.index(after: trimmed.startIndex)..<arrowRange.lowerBound])
            let state = trimmed[arrowRange.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            if state == "disabled" || state == "true" {
                disabled.insert(label)
            }
        }
        return disabled
    }

    private func terminateRunningLoginItem(
        bundleID: String,
        name: String,
        path: String,
        executablePath: String?
    ) async {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        let matchingPIDs: [pid_t] = await MainActor.run {
            var pids: [pid_t] = []
            for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
                let matchesBundle = !bundleID.isEmpty && app.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
                let matchesPath = path.hasPrefix("/") && app.bundleURL?.path == path
                let matchesExec = executablePath != nil && app.executableURL?.path == executablePath
                let matchesName = !name.isEmpty && app.localizedName?.caseInsensitiveCompare(name) == .orderedSame
                if matchesBundle || matchesPath || matchesExec || matchesName {
                    _ = app.forceTerminate()
                    pids.append(app.processIdentifier)
                }
            }
            return pids
        }
        for pid in matchingPIDs where pid > 0 {
            _ = Darwin.kill(pid, SIGKILL)
        }
        if let execPath = executablePath, execPath.hasPrefix("/") {
            _ = try? await commandRunner.run(command: "/usr/bin/pkill", arguments: ["-9", "-f", execPath])
        } else if !name.isEmpty, name.count >= 4 {
            _ = try? await commandRunner.run(command: "/usr/bin/killall", arguments: ["-9", name])
        }
    }

    public func delete(service: StartupService, bypassTrash: Bool = false) async throws {
        guard service.category != .system, !service.requiresRoot, !service.path.hasPrefix("/System/") else {
            throw SafetyError.protectedPath(service.path)
        }

        await LaunchdControl.bootout(plistPath: service.path, label: service.id, runner: commandRunner)
        _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["disable", "gui/\(getuid())/\(service.id)"])

        let plistURL = URL(fileURLWithPath: service.path)
        try await trashManager.removeItem(at: plistURL, bypassTrash: bypassTrash, policy: .uninstall)
    }

    public func addVendorPrefix(_ prefix: String) {
        var prefixes = systemVendorPrefixes
        if !prefixes.contains(prefix) {
            prefixes.append(prefix)
            systemVendorPrefixes = prefixes
        }
    }

    public func removeVendorPrefix(_ prefix: String) {
        guard prefix != "com.apple." else { return }
        systemVendorPrefixes = systemVendorPrefixes.filter { $0 != prefix }
    }

    public func setSystemVendorPrefixes(_ prefixes: [String]) {
        var updated = prefixes
        if !updated.contains("com.apple.") {
            updated.append("com.apple.")
        }
        systemVendorPrefixes = updated
    }
}
