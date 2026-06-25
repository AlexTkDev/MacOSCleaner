import Foundation

public actor AppDiscovery {
    private let fileManager: FileManager
    private let commandRunner: CommandRunner

    public init(fileManager: FileManager = .default, commandRunner: CommandRunner = CommandRunner()) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    public func findAll() async -> [URL] {
        var urls: [URL] = []

        // Standard app directories
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: "\(NSHomeDirectory())/Applications"),
        ].compactMap { $0 }

        for dir in appDirs {
            if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                urls.append(contentsOf: contents.filter { $0.pathExtension == "app" })
            }
        }

        // Application Support (Google Updater, etc.)
        let appSupport = "\(NSHomeDirectory())/Library/Application Support"
        if let result = try? await commandRunner.run(
            command: "/usr/bin/find",
            arguments: [appSupport, "-maxdepth", "4", "-name", "*.app", "-type", "d", "-prune"]
        ) {
            for path in result.stdout.components(separatedBy: .newlines) where !path.isEmpty {
                urls.append(URL(fileURLWithPath: path))
            }
        }

        // Dev build products (DerivedData)
        let derivedData = "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData"
        if let result = try? await commandRunner.run(
            command: "/usr/bin/find",
            arguments: [derivedData, "-maxdepth", "5", "-name", "*.app", "-type", "d", "-prune"]
        ) {
            for path in result.stdout.components(separatedBy: .newlines) where !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                if !url.path.contains("/Applications/") {
                    urls.append(url)
                }
            }
        }

        return Array(Set(urls))
    }
}
