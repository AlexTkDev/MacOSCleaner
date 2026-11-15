import Foundation

enum LaunchdControl {
    /// Unload a user LaunchAgent plist via modern `launchctl bootout` before removal.
    static func bootout(plistPath: String, runner: CommandRunner) async {
        guard plistPath.hasSuffix(".plist"),
              plistPath.contains("LaunchAgents") || plistPath.contains("LaunchDaemons") else {
            return
        }
        // System daemons require root privileges; skip without elevation prompt.
        guard !plistPath.hasPrefix("/Library/LaunchDaemons/"),
              !plistPath.hasPrefix("/System/") else {
            return
        }

        let domain = "gui/\(getuid())"
        let label = extractLabel(from: plistPath)
            ?? URL(fileURLWithPath: plistPath).deletingPathExtension().lastPathComponent
        let target = "\(domain)/\(label)"
        let byLabel = try? await runner.run(command: "/bin/launchctl", arguments: ["bootout", target])
        if byLabel?.exitCode != 0 {
            _ = try? await runner.run(command: "/bin/launchctl", arguments: ["bootout", domain, plistPath])
        }
    }

    private static func extractLabel(from plistPath: String) -> String? {
        let url = URL(fileURLWithPath: plistPath)
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let label = plist["Label"] as? String,
              !label.isEmpty else {
            return nil
        }
        return label
    }
}
