import Foundation
import Security

public struct CodeSignatureInfo: Codable, Equatable, Sendable {
    public let isSigned: Bool
    public let isValid: Bool
    public let isAppleSigned: Bool
    public let isAdHoc: Bool
    public let isNotarized: Bool
    public let teamID: String?
    public let authority: String?
    public let cdhash: String?

    public init(
        isSigned: Bool,
        isValid: Bool = true,
        isAppleSigned: Bool = false,
        isAdHoc: Bool = false,
        isNotarized: Bool = false,
        teamID: String? = nil,
        authority: String? = nil,
        cdhash: String? = nil
    ) {
        self.isSigned = isSigned
        self.isValid = isSigned ? isValid : false
        self.isAppleSigned = isAppleSigned
        self.isAdHoc = isAdHoc
        self.isNotarized = isNotarized
        self.teamID = teamID
        self.authority = authority
        self.cdhash = cdhash
    }

    /// In-process SecStaticCode check with `kSecCSNoNetworkAccess` so signature inspection never triggers network calls.
    public static func check(path: String) async -> CodeSignatureInfo {
        await Task.detached(priority: .utility) {
            checkStaticCode(at: path)
        }.value
    }

    private static func checkStaticCode(at path: String) -> CodeSignatureInfo {
        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode else {
            return CodeSignatureInfo(isSigned: false, isValid: false)
        }

        // Validate signature offline; errSecCSUnsigned means no signature at all.
        let validityStatus = SecStaticCodeCheckValidity(code, .noNetworkAccess, nil)
        if validityStatus == errSecCSUnsigned {
            return CodeSignatureInfo(isSigned: false, isValid: false)
        }
        let isValid = validityStatus == errSecSuccess

        var infoRef: CFDictionary?
        let infoFlags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSContentInformation)
        guard SecCodeCopySigningInformation(code, infoFlags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            return CodeSignatureInfo(isSigned: true, isValid: isValid)
        }

        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let rawFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = (rawFlags & SecCodeSignatureFlags.adhoc.rawValue) != 0

        var authority: String?
        if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certs.first {
            authority = SecCertificateCopySubjectSummary(leaf) as String?
        }

        var isAppleSigned = false
        var appleReq: SecRequirement?
        if SecRequirementCreateWithString("anchor apple" as CFString, SecCSFlags(), &appleReq) == errSecSuccess,
           let req = appleReq {
            isAppleSigned = SecStaticCodeCheckValidity(code, .noNetworkAccess, req) == errSecSuccess
        }

        var isNotarized = info[kSecCodeInfoStapledNotarizationTicket as String] != nil
        if !isNotarized, let appBundleURL = enclosingAppBundleURL(for: path) {
            isNotarized = hasStapledNotarizationTicket(at: appBundleURL)
        }

        return CodeSignatureInfo(
            isSigned: true,
            isValid: isValid,
            isAppleSigned: isAppleSigned,
            isAdHoc: isAdHoc,
            isNotarized: isNotarized,
            teamID: teamID,
            authority: authority,
            cdhash: nil
        )
    }

    private static func enclosingAppBundleURL(for path: String) -> URL? {
        guard let range = path.range(of: ".app/Contents/") else { return nil }
        let appPath = String(path[..<range.lowerBound]) + ".app"
        return URL(fileURLWithPath: appPath)
    }

    private static func hasStapledNotarizationTicket(at bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode else {
            return false
        }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSContentInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            return false
        }
        return info[kSecCodeInfoStapledNotarizationTicket as String] != nil
    }

    public static func check(path: String, commandRunner: any CommandRunning) async -> CodeSignatureInfo {
        let url = URL(fileURLWithPath: path)
        do {
            let result = try await commandRunner.run(
                command: "/usr/bin/codesign",
                arguments: ["--display", "--verbose=2", "--signing", "-", url.path]
            )
            guard result.exitCode == 0 else {
                return CodeSignatureInfo(isSigned: false, isValid: false)
            }

            let output = result.stdout + "\n" + result.stderr
            let teamID = extractValues(from: output, key: "TeamIdentifier").first
            let authorities = extractValues(from: output, key: "Authority")
            let authority = authorities.first
            let isAppleSigned = authorities.contains { $0.contains("Apple") }
            let isAdHoc = output.contains("Signature=adhoc")

            return CodeSignatureInfo(
                isSigned: true,
                isValid: true,
                isAppleSigned: isAppleSigned,
                isAdHoc: isAdHoc,
                isNotarized: false,
                teamID: teamID,
                authority: authority,
                cdhash: nil
            )
        } catch {
            return CodeSignatureInfo(isSigned: false, isValid: false)
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
