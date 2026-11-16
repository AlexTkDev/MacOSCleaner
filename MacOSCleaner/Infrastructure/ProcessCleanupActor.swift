import Foundation

public actor ProcessCleanupActor {
    private let commandRunner: any CommandRunning
    private let commandCache: CommandCache
    private let fm = FileManager.default

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        commandCache: CommandCache = CommandCache()
    ) {
        self.commandRunner = commandRunner
        self.commandCache = commandCache
    }

    func commandExists(_ command: String) async -> Bool {
        await commandCache.resolve(command, runner: commandRunner)
    }

    func run(command: String, arguments: [String], timeout: Duration = .seconds(30)) async throws -> CommandResult {
        try await commandRunner.run(command: command, arguments: arguments, timeout: timeout)
    }

    func withUserPath(_ command: String) -> String {
        let home = fm.homeDirectoryForCurrentUser.path
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shellPath as NSString).lastPathComponent
        let defaultPathPrefix = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:$PATH\""

        switch shellName {
        case "fish":
            return "fish -c 'source \"\(home)/.config/fish/config.fish\" 2>/dev/null; \(command.replacingOccurrences(of: "'", with: "\\'"))' </dev/null"
        case "nushell", "nu":
            return "nu -c 'source \"\(home)/.config/nushell/env.nu\" 2>/dev/null; source \"\(home)/.config/nushell/config.nu\" 2>/dev/null; \(command.replacingOccurrences(of: "'", with: "\\'"))' </dev/null"
        case "bash":
            return """
            \(defaultPathPrefix); \
            if [ -f "\(home)/.bash_profile" ]; then source "\(home)/.bash_profile" 2>/dev/null; \
            elif [ -f "\(home)/.bashrc" ]; then source "\(home)/.bashrc" 2>/dev/null; fi; \
            \(command) </dev/null
            """
        default:
            // Avoid sourcing ~/.zshrc inside /bin/bash; invoke zsh directly with stdin detached.
            let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
            return "\(defaultPathPrefix); zsh -c 'if [ -f \"\(home)/.zprofile\" ]; then source \"\(home)/.zprofile\" 2>/dev/null; fi; if [ -f \"\(home)/.zshrc\" ]; then source \"\(home)/.zshrc\" 2>/dev/null; fi; \(escaped)' </dev/null"
        }
    }
}
