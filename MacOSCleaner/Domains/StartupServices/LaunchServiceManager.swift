import Foundation

public enum LaunchServiceError: Error {
    case scanFailed(String)
    case toggleFailed(String)
    case invalidPlist(String)
}

public actor LaunchServiceManager {
    private let commandRunner: CommandRunner
    private let safetyManager: SafetyManager
    private let fileManager: FileManager
    private let searchPaths: [String]
    
    public init(
        commandRunner: CommandRunner = CommandRunner(),
        safetyManager: SafetyManager = SafetyManager(),
        fileManager: FileManager = .default,
        searchPaths: [String]? = nil
    ) {
        self.commandRunner = commandRunner
        self.safetyManager = safetyManager
        self.fileManager = fileManager
        
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
        
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            
            // Safety check
            do {
                try safetyManager.validate(url: url)
            } catch {
                // If a path is blocked, skip it instead of failing the whole scan
                continue
            }
            
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
                    allServices.append(StartupService(
                        id: label,
                        name: label,
                        path: plistURL.path,
                        isEnabled: isEnabled
                    ))
                }
            }
        }
        
        // Remove duplicates by label (label is ID)
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
        
        // 1. Get from user launchctl list
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
        
        // 2. Get from system launchctl print system (to find daemons)
        // We look for labels in the "services = {" section
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
                // Typical line: "515 - com.apple.runningboardd"
                // Or: "0 0 com.example.service"
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3 {
                    labels.insert(parts[2])
                }
            }
        }
        return labels
    }
    
    private func extractLabel(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist["Label"] as? String
    }
    
    public func disable(service: StartupService) async throws {
        let result = try await commandRunner.run(
            command: "/bin/launchctl",
            arguments: ["unload", "-w", service.path]
        )
        
        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("no such process") || stderr.contains("could not find service") {
                return
            }
            throw LaunchServiceError.toggleFailed(result.stderr)
        }
    }
    
    public func enable(service: StartupService) async throws {
        let result = try await commandRunner.run(
            command: "/bin/launchctl",
            arguments: ["load", "-w", service.path]
        )
        
        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("already loaded") {
                return
            }
            throw LaunchServiceError.toggleFailed(result.stderr)
        }
    }
}
