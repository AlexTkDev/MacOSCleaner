import Foundation

public actor BackgroundItemsReader {
    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func readLaunchAgents() async -> Set<URL> {
        let paths = [
            NormalizedPath.joinHome(NSHomeDirectory(), "Library/LaunchAgents"),
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]
        var urls = Set<URL>()
        for path in paths {
            let dir = NormalizedPath.url(path, isDirectory: true)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for url in contents where url.pathExtension == "plist" {
                urls.insert(NormalizedPath.canonicalize(url))
            }
        }
        return NormalizedPath.urls(urls)
    }

    public func readLoginItems() async -> Set<URL> {
        var urls = Set<URL>()
        let result = try? await commandRunner.run(
            command: "/usr/bin/sfltool",
            arguments: ["dumpbtm"]
        )
        if let output = result?.stdout {
            for rawLine in output.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("URL:") {
                    let rawURL = String(line.dropFirst("URL:".count)).trimmingCharacters(in: .whitespaces)
                    if let parsed = URL(string: rawURL), parsed.isFileURL {
                        urls.insert(NormalizedPath.canonicalize(parsed))
                    }
                } else if line.hasPrefix("Executable Path:") {
                    let path = String(line.dropFirst("Executable Path:".count)).trimmingCharacters(in: .whitespaces)
                    if path.hasPrefix("/") {
                        urls.insert(NormalizedPath.url(path))
                    }
                }
            }
        }
        return NormalizedPath.urls(urls)
    }
}
