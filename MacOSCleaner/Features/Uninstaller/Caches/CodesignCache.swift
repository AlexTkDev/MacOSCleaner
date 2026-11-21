import Foundation
import Security

public actor CodesignCache {
    public struct SigningInfo: Sendable {
        public let teamID: String?
        public let authorities: [String]

        public static let unsigned = SigningInfo(teamID: nil, authorities: [])
    }

    private static let signableExtensions: Set<String> = [
        "app", "bundle", "kext", "framework", "xpc", "plugin", "appex",
        "driver", "component", "prefpane", "qlgenerator", "saver",
        "mdimporter", "systemextension", "dylib", "so"
    ]

    private var cache: [String: SigningInfo] = [:]
    private let maxEntries = 2048

    public init() {}

    public static func isSignableCandidate(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if signableExtensions.contains(ext) {
            return true
        }
        if ext.isEmpty {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                return false
            }
            // Plain data directories without bundle extensions are never Mach-O/bundle code objects.
            return !isDir.boolValue
        }
        return false
    }

    public func getSigningInfo(url: URL) -> SigningInfo {
        let key = NormalizedPath.key(url)
        if let cached = cache[key] {
            return cached
        }
        guard Self.isSignableCandidate(url: url) else {
            return .unsigned
        }
        let info = Self.readSigningInfo(at: url)
        if cache.count >= maxEntries {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = info
        return info
    }

    public func getTeamID(url: URL, commandRunner: any CommandRunning) async -> String? {
        getSigningInfo(url: url).teamID
    }

    private static func readSigningInfo(at url: URL) -> SigningInfo {
        autoreleasepool {
            var staticCode: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
                  let code = staticCode else {
                return .unsigned
            }
            var infoRef: CFDictionary?
            let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
            guard SecCodeCopySigningInformation(code, flags, &infoRef) == errSecSuccess,
                  let info = infoRef as? [String: Any] else {
                return .unsigned
            }

            let rawTeam = (info[kSecCodeInfoTeamIdentifier as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let teamID = (rawTeam?.isEmpty == false) ? rawTeam : nil

            var authorities: [String] = []
            if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate] {
                authorities.reserveCapacity(certs.count)
                for cert in certs {
                    if let summary = SecCertificateCopySubjectSummary(cert) as String?, !summary.isEmpty {
                        authorities.append(summary)
                    }
                }
            }

            return SigningInfo(teamID: teamID, authorities: authorities)
        }
    }
}
