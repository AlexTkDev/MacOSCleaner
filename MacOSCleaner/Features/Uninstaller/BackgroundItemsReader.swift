import Foundation

public actor BackgroundItemsReader {
    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func readLaunchAgents() async -> Set<URL> {
        let paths = [
            "\(NSHomeDirectory())/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]
        var urls = Set<URL>()
        for path in paths {
            let dir = URL(fileURLWithPath: path)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for url in contents where url.pathExtension == "plist" {
                urls.insert(url)
            }
        }
        return urls
    }

    public func readLoginItems() async -> Set<URL> {
        var urls = Set<URL>()
        let result = try? await commandRunner.run(
            command: "/usr/bin/osascript",
            arguments: ["-e", "tell application \"System Events\" to get the path of every login item"]
        )
        if let output = result?.stdout {
            for line in output.components(separatedBy: ",") where !line.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    urls.insert(URL(fileURLWithPath: trimmed))
                }
            }
        }
        return urls
    }
}
