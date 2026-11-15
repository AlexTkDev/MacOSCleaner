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

    public static func check(path: String, commandRunner: any CommandRunning = CommandRunner()) async -> CodeSignatureInfo {
        let url = URL(fileURLWithPath: path)
        do {
            let result = try await commandRunner.run(
                command: "/usr/bin/codesign",
                arguments: ["--display", "--verbose=2", "--signing", "-", url.path]
            )
            guard result.exitCode == 0 else {
                return CodeSignatureInfo(isSigned: false)
            }

            let output = result.stdout + "\n" + result.stderr
            let teamID = extractValues(from: output, key: "TeamIdentifier").first
            let authorities = extractValues(from: output, key: "Authority")
            let authority = authorities.first
            let isAppleSigned = authorities.contains { $0.contains("Apple") }

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

    private static func extractValues(from output: String, key: String) -> [String] {
        output.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            for separator in ["=", ":"] {
                let prefix = key + separator
                if line.hasPrefix(prefix) {
                    let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                }
            }
            return nil
        }
    }
}
