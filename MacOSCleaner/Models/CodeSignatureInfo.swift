import Foundation
import Security

public struct CodeSignatureInfo: Sendable {
    public let isSigned: Bool
    public let isAppleSigned: Bool
    public let teamID: String?
    public let authority: String?
    public let cdhash: String?

    public init(
        isSigned: Bool,
        isAppleSigned: Bool = false,
        teamID: String? = nil,
        authority: String? = nil,
        cdhash: String? = nil
    ) {
        self.isSigned = isSigned
        self.isAppleSigned = isAppleSigned
        self.teamID = teamID
        self.authority = authority
        self.cdhash = cdhash
    }

    public static func check(path: String) -> CodeSignatureInfo {
        let url = URL(fileURLWithPath: path)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--display", "--verbose=2", "--signing", "-", url.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""

            guard task.terminationStatus == 0 else {
                return CodeSignatureInfo(isSigned: false)
            }

            let teamID = extractValue(from: output, key: "TeamIdentifier")
            let authority = extractValue(from: output, key: "Authority")
            let isAppleSigned = authority?.contains("Apple") == true || teamID == nil

            return CodeSignatureInfo(
                isSigned: true,
                isAppleSigned: isAppleSigned,
                teamID: teamID,
                authority: authority,
                cdhash: nil
            )
        } catch {
            return CodeSignatureInfo(isSigned: false)
        }
    }

    private static func extractValue(from output: String, key: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(key) {
                let components = line.components(separatedBy: ":")
                guard components.count >= 2 else { continue }
                let value = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}
