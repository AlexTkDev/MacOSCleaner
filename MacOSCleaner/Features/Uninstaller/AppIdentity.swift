import Foundation
import Security

public struct AppIdentity: Sendable, Hashable {
    public let bundleID: String
    public let appName: String
    public let bundleName: String?
    public let bundleVersion: String?
    public let executableName: String
    public let teamID: String?
    public let signingAuthority: String?
    public let bundleURL: URL
    public let isAppStore: Bool
    public let isSandboxed: Bool
    public let isAdHocSigned: Bool

    public let vendorNames: Set<String>
    public let helperNames: Set<String>
    public let frameworkNames: Set<String>
    public let xpcServiceNames: Set<String>
    public let plugInNames: Set<String>
    /// App groups from the code signature entitlements
    /// (com.apple.security.application-groups) — ground truth for Group Containers.
    public var appGroups: Set<String> = []

    public let isElectron: Bool
    public let isJetBrains: Bool
    public let isFlutter: Bool
    public let isJava: Bool
    public let isQt: Bool
    public let isDocker: Bool
}

public extension AppIdentity {
    static func resolve(from url: URL, commandRunner: CommandRunner = CommandRunner()) async -> AppIdentity {
        let (bundleID, appName, bundleName, bundleVersion, executableName, signing, isAppStore) = autoreleasepool {
            let bundle = Bundle(url: url)
            let bid = bundle?.bundleIdentifier ?? "unknown.\(url.deletingPathExtension().lastPathComponent)"
            let name = url.deletingPathExtension().lastPathComponent
            let bName = bundle?.infoDictionary?["CFBundleName"] as? String
            let bVersion = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
            let execName = bundle?.infoDictionary?["CFBundleExecutable"] as? String ?? name
            let signMeta = extractSigningMetadata(url: url)
            let mas = fileExists(at: url.appendingPathComponent("Contents/_MASReceipt"))
            return (bid, name, bName, bVersion, execName, signMeta, mas)
        }
        let teamID = signing.teamID
        let authority = signing.authority
        let isAdHoc = signing.isAdHoc
        let isSandboxed = signing.isSandboxed
        let appGroups = signing.appGroups

        let frameworkNames = await scanFrameworks(url: url)
        let xpcServiceNames = await scanXPCServices(url: url)
        let plugInNames = await scanPlugIns(url: url)

        let isElectron = frameworkNames.contains { $0.lowercased().contains("electron") }
        let isFlutter = frameworkNames.contains { $0.lowercased().contains("flutter") }
            || frameworkNames.contains { $0.lowercased().contains("dart") }
        let isJava = plugInNames.contains { $0.lowercased().contains("jdk") || $0.lowercased().contains("jre") }
        let isQt = frameworkNames.contains { $0.lowercased().hasPrefix("qt") }
        let isDocker = bundleID.lowercased() == "com.docker.docker"
            || bundleID.lowercased() == "com.docker.orbstack"
            || url.path.lowercased().contains("orbstack")
        let isJetBrains = bundleID.lowercased().contains("jetbrains")
            || authority?.lowercased().contains("jetbrains") == true

        let helperNames = await scanHelpers(url: url)
        let vendorNames = deriveVendorNames(bundleID: bundleID, appName: appName, authority: authority)

        return AppIdentity(
            bundleID: bundleID,
            appName: appName,
            bundleName: bundleName,
            bundleVersion: bundleVersion,
            executableName: executableName,
            teamID: teamID,
            signingAuthority: authority,
            bundleURL: url,
            isAppStore: isAppStore,
            isSandboxed: isSandboxed,
            isAdHocSigned: isAdHoc,
            vendorNames: vendorNames,
            helperNames: helperNames,
            frameworkNames: frameworkNames,
            xpcServiceNames: xpcServiceNames,
            plugInNames: plugInNames,
            appGroups: appGroups,
            isElectron: isElectron,
            isJetBrains: isJetBrains,
            isFlutter: isFlutter,
            isJava: isJava,
            isQt: isQt,
            isDocker: isDocker
        )
    }
}

// MARK: - Private helpers

private struct SigningMetadata {
    let teamID: String?
    let authority: String?
    let isAdHoc: Bool
    let isSandboxed: Bool
    let appGroups: Set<String>

    static let unsigned = SigningMetadata(
        teamID: nil,
        authority: nil,
        isAdHoc: false,
        isSandboxed: false,
        appGroups: []
    )
}

/// In-process code-signing metadata lookup (no subprocess spawn, no network, no full-bundle hashing).
private func extractSigningMetadata(url: URL) -> SigningMetadata {
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

    let rawFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
    let isAdHoc = (rawFlags & SecCodeSignatureFlags.adhoc.rawValue) != 0

    var authority: String?
    if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
       let leaf = certs.first {
        authority = SecCertificateCopySubjectSummary(leaf) as String?
    }

    let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    let isSandboxed = entitlements?["com.apple.security.app-sandbox"] as? Bool ?? false
    let appGroups = Set(entitlements?["com.apple.security.application-groups"] as? [String] ?? [])

    return SigningMetadata(
        teamID: teamID,
        authority: authority,
        isAdHoc: isAdHoc,
        isSandboxed: isSandboxed,
        appGroups: appGroups
    )
}

private func fileExists(at path: URL) -> Bool {
    FileManager.default.fileExists(atPath: path.path)
}

private func scanFrameworks(url: URL) async -> Set<String> {
    let fm = FileManager.default
    let frameworksURL = url.appendingPathComponent("Contents/Frameworks")
    guard let items = try? fm.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil) else { return [] }
    return Set(items.compactMap { $0.pathExtension == "framework" ? $0.deletingPathExtension().lastPathComponent : nil })
}

private func scanXPCServices(url: URL) async -> Set<String> {
    let fm = FileManager.default
    let xpcURL = url.appendingPathComponent("Contents/XPCServices")
    guard let items = try? fm.contentsOfDirectory(at: xpcURL, includingPropertiesForKeys: nil) else { return [] }
    return Set(items.compactMap { $0.pathExtension == "xpc" ? $0.deletingPathExtension().lastPathComponent : nil })
}

private func scanPlugIns(url: URL) async -> Set<String> {
    let fm = FileManager.default
    let plugInsURL = url.appendingPathComponent("Contents/PlugIns")
    guard let items = try? fm.contentsOfDirectory(at: plugInsURL, includingPropertiesForKeys: nil) else { return [] }
    return Set(items.compactMap { $0.pathExtension == "bundle" ? $0.deletingPathExtension().lastPathComponent : $0.lastPathComponent })
}

public let genericFrameworkTokens: Set<String> = [
    "gpu", "net", "framework", "electron", "chromium", "core", "ui", "audio", "video",
    "mantle", "sparkle", "crashlytics", "sentry", "webrtc", "ffmpeg"
]

private func scanHelpers(url: URL) async -> Set<String> {
    let fm = FileManager.default
    let frameworksURL = url.appendingPathComponent("Contents/Frameworks")
    guard let items = try? fm.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil) else { return [] }
    let helperItems = items.filter { item in
        let lower = item.lastPathComponent.lowercased()
        return lower.contains("helper") || lower.contains("framework")
    }
    let extracted = helperItems.map { $0.deletingPathExtension().lastPathComponent }
    return Set(extracted.filter { name in
        let lower = name.lowercased()
        if genericFrameworkTokens.contains(lower) { return false }
        if lower.count < 3 { return false }
        return true
    })
}

// "apple" is a stopword: deriving vendor "Apple" from com.apple.* bundle IDs makes
// OS-owned dirs like /Library/Application Support/Apple match as residuals.
private let vendorStopwords: Set<String> = ["com", "org", "net", "io", "app", "co", "inc", "ltd", "llc", "uk", "us", "eu", "apple"]

private func deriveVendorNames(bundleID: String, appName: String, authority: String?) -> Set<String> {
    var names = Set<String>()
    let parts = bundleID.components(separatedBy: ".")
    // The last component of a 3+-part reverse-DNS ID is the product, not the vendor.
    // Deriving "desktop" from ai.opencode.desktop (or "chrome" from com.google.Chrome)
    // turns generic folder names anywhere on disk into vendor matches.
    let vendorParts = parts.count >= 3 ? Array(parts.dropLast()) : parts

    for p in vendorParts where p.count >= 4 && !vendorStopwords.contains(p.lowercased()) {
        names.insert(p)
        names.insert(p.capitalized)
        names.insert(p.prefix(1).uppercased() + p.dropFirst())
    }
    if let first = vendorParts.first(where: { $0.count >= 4 && !vendorStopwords.contains($0.lowercased()) }) {
        names.insert(first.capitalized)
    }

    if !appName.isEmpty {
        names.insert(appName)
        names.insert(appName.replacingOccurrences(of: " ", with: ""))
    }
    if let auth = authority {
        let orgRegex = try? NSRegularExpression(pattern: "(?<=: )[^,]+")
        if let match = orgRegex?.firstMatch(in: auth, range: NSRange(auth.startIndex..., in: auth)),
           let range = Range(match.range, in: auth) {
            let org = String(auth[range]).trimmingCharacters(in: .whitespaces)
            names.insert(org)
        }
    }

    let staticAliases: [String: Set<String>] = [
        "jetbrains": ["JetBrains", "IntelliJ", "PyCharm", "DataGrip", "GoLand", "WebStorm", "RubyMine", "CLion", "Rider", "AppCode"],
        "adobe": ["Adobe"],
        "microsoft": ["Microsoft", "Office", "Teams", "VSCode"],
        "google": ["Google"],
        "docker": ["Docker"],
        "oracle": ["Oracle"],
    ]
    for (key, aliases) in staticAliases {
        if bundleID.lowercased().contains(key) || appName.lowercased().contains(key) {
            names.formUnion(aliases)
        }
    }

    return names
}
