import Foundation

enum LaunchdControl {
    /// Unload a plist before it is removed. System daemons need an admin `bootout`.
    static func bootout(plistPath: String, runner: CommandRunner) async {
        guard plistPath.hasSuffix(".plist"),
              plistPath.contains("LaunchAgents") || plistPath.contains("LaunchDaemons") else {
            return
        }
        if plistPath.hasPrefix("/Library/LaunchDaemons/") {
            let label = URL(fileURLWithPath: plistPath).deletingPathExtension().lastPathComponent
            let command = "/bin/launchctl bootout system/\(ShellQuoting.shellQuoted(label))"
            _ = try? await PrivilegedTaskRunner.runAsAdmin(command: command)
            return
        }
        let domain = plistPath.contains("LaunchDaemons") ? "system" : "gui/\(getuid())"
        let bootout = try? await runner.run(command: "/bin/launchctl", arguments: ["bootout", domain, plistPath])
        if bootout?.exitCode != 0 {
            _ = try? await runner.run(command: "/bin/launchctl", arguments: ["unload", "-w", plistPath])
        }
    }
}
