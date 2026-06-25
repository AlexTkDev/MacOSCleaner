import Foundation

public actor CodesignCache {
    private var cache: [String: String] = [:]

    public init() {}

    public func getTeamID(url: URL, commandRunner: any CommandRunning) async -> String? {
        let key = url.standardizedFileURL.path
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }

        let result = try? await commandRunner.run(command: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", key])
        guard let output = result?.stderr else {
            cache[key] = ""
            return nil
        }
        if let range = output.range(of: "TeamIdentifier=") {
            let start = range.upperBound
            let end = output[start...].firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? output.endIndex
            let teamID = String(output[start..<end])
            cache[key] = teamID
            return teamID
        }
        cache[key] = ""
        return nil
    }
}
