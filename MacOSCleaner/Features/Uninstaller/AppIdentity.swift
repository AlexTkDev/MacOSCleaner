import Foundation

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

    public let isElectron: Bool
    public let isJetBrains: Bool
    public let isFlutter: Bool
    public let isJava: Bool
    public let isQt: Bool
    public let isDocker: Bool
}

public extension AppIdentity {
    static func resolve(from url: URL, commandRunner: CommandRunner = CommandRunner()) async -> AppIdentity {
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier ?? "unknown.\(url.deletingPathExtension().lastPathComponent)"
        let appName = url.deletingPathExtension().lastPathComponent
        let bundleName = bundle?.infoDictionary?["CFBundleName"] as? String
        let bundleVersion = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
        let executableName = bundle?.infoDictionary?["CFBundleExecutable"] as? String ?? appName

        let teamID = await extractTeamID(url: url, commandRunner: commandRunner)
        let authority = await extractSigningAuthority(url: url, commandRunner: commandRunner)
        let isAdHoc = authority?.contains("Ad Hoc") == true || authority?.contains("not signed") == true
        let isAppStore = fileExists(at: url.appendingPathComponent("Contents/_MASReceipt"))
        let isSandboxed = await checkSandbox(url: url, commandRunner: commandRunner)

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

private func extractTeamID(url: URL, commandRunner: CommandRunner) async -> String? {
    let result = try? await commandRunner.run(command: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", url.path])
    guard let output = result?.stderr else { return nil }
    if let range = output.range(of: "TeamIdentifier=") {
        let start = range.upperBound
        let end = output[start...].firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? output.endIndex
        return String(output[start..<end])
    }
    return nil
}

private func extractSigningAuthority(url: URL, commandRunner: CommandRunner) async -> String? {
    let result = try? await commandRunner.run(command: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", url.path])
    guard let output = result?.stderr else { return nil }
    if let range = output.range(of: "Authority=") {
        let start = range.upperBound
        let end = output[start...].firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? output.endIndex
        return String(output[start..<end])
    }
    return nil
}

private func checkSandbox(url: URL, commandRunner: CommandRunner) async -> Bool {
    let result = try? await commandRunner.run(command: "/usr/bin/codesign", arguments: ["-d", "--entitlements", ":-", url.path])
    guard let output = result?.stdout else { return false }
    return output.contains("com.apple.security.app-sandbox")
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

private func scanHelpers(url: URL) async -> Set<String> {
    let fm = FileManager.default
    let frameworksURL = url.appendingPathComponent("Contents/Frameworks")
    guard let items = try? fm.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil) else { return [] }
    let helperNames = items.filter { $0.lastPathComponent.lowercased().contains("helper") || $0.lastPathComponent.lowercased().contains("framework") }
    return Set(helperNames.map { $0.deletingPathExtension().lastPathComponent })
}

// "apple" is a stopword: deriving vendor "Apple" from com.apple.* bundle IDs makes
// OS-owned dirs like /Library/Application Support/Apple match as residuals.
private let vendorStopwords: Set<String> = ["com", "org", "net", "io", "app", "co", "inc", "ltd", "llc", "uk", "us", "eu", "apple"]

private func deriveVendorNames(bundleID: String, appName: String, authority: String?) -> Set<String> {
    var names = Set<String>()
    let parts = bundleID.components(separatedBy: ".")

    for p in parts where p.count >= 4 && !vendorStopwords.contains(p.lowercased()) {
        names.insert(p)
        names.insert(p.capitalized)
        names.insert(p.prefix(1).uppercased() + p.dropFirst())
    }
    if let first = parts.first(where: { $0.count >= 4 && !vendorStopwords.contains($0.lowercased()) }) {
        names.insert(first.capitalized)
    }

    if !appName.isEmpty {
        names.insert(appName)
        names.insert(appName.replacingOccurrences(of: " ", with: ""))
    }
    if let auth = authority {
        let orgRegex = try? NSRegularExpression(pattern: "(?<=: )[^,]+")
        if let match = orgRegex?.firstMatch(in: auth, range: NSRange(auth.startIndex..., in: auth)) {
            let org = String(auth[Range(match.range, in: auth)!]).trimmingCharacters(in: .whitespaces)
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
