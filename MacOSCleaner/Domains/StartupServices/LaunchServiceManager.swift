import Foundation

public enum LaunchServiceError: Error {
    case scanFailed(String)
    case toggleFailed(String)
    case invalidPlist(String)
}

public actor LaunchServiceManager {
    private let commandRunner: CommandRunner
    private let fileManager: FileManager
    private let trashManager: TrashManager
    private let searchPaths: [String]

    private static let vendorPrefixesKey = "startupSystemVendorPrefixes"
    private static let defaultVendorPrefixes = ["com.apple."]

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
        trashManager: TrashManager? = nil
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.trashManager = trashManager ?? TrashManager()

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
                if let label = extractLabel(from: plistURL) {
                    let isEnabled = loadedLabels.contains(label)
                    let category = categorize(path: plistURL.path, label: label, prefixes: prefixes)
                    allServices.append(StartupService(
                        id: label,
                        name: label,
                        path: plistURL.path,
                        isEnabled: isEnabled,
                        category: category
                    ))
                }
            }
        }

        var uniqueServices: [String: StartupService] = [:]
        for service in allServices {
            if uniqueServices[service.id] == nil {
                uniqueServices[service.id] = service
            }
        }

        return Array(uniqueServices.values).sorted { $0.name < $1.name }
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

    private func extractLabel(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist["Label"] as? String
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

    public func delete(service: StartupService) async throws {
        guard service.category != .system, !service.requiresRoot, !service.path.hasPrefix("/System/") else {
            throw SafetyError.protectedPath(service.path)
        }

        await LaunchdControl.bootout(plistPath: service.path, runner: commandRunner)
        _ = try? await commandRunner.run(command: "/bin/launchctl", arguments: ["disable", "gui/\(getuid())/\(service.id)"])

        // Trash the plist file with .uninstall policy
        let plistURL = URL(fileURLWithPath: service.path)
        try await trashManager.trashItem(at: plistURL, policy: .uninstall)
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
