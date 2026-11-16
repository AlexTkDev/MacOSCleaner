import Foundation

public enum LaunchServiceError: Error {
    case toggleFailed(String)
}

public actor LaunchServiceManager {
    private let commandRunner: CommandRunner
    private let fileManager: FileManager
    private let trashManager: TrashManager
    private let backgroundItemsReader: BackgroundItemsReader
    private let signatureChecker: @Sendable (String) async -> CodeSignatureInfo
    private let searchPaths: [String]

    private static let vendorPrefixesKey = "startupSystemVendorPrefixes"
    private static let defaultVendorPrefixes = ["com.apple."]
    private static let maxConcurrentSignatureChecks = 6

    public var systemVendorPrefixes: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: Self.vendorPrefixesKey) ?? Self.defaultVendorPrefixes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.vendorPrefixesKey)
        }
    }

    public init(
        commandRunner: CommandRunner = CommandRunner(),
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

        let services = try await servicesTask
        let snapshot = await btmTask

        let rawLoginItems = snapshot.items.map { item -> StartupService in
            let targetPath = item.executablePath ?? item.url?.path
            let displayPath = item.url?.path ?? item.executablePath ?? item.identifier
            let exists = targetPath.map { fileManager.fileExists(atPath: $0) } ?? true
            return StartupService(
                id: item.id,
                name: item.name,
                path: displayPath,
                isEnabled: item.isEnabled,
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

        let domain = "gui/\(getuid())"
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

        let domain = "gui/\(getuid())"
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
