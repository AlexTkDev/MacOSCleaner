#!/usr/bin/env swift
// Generate MacOSCleaner/Domains/Cleanup/GeneratedCleanupPaths.swift from engine_paths.json (v3).
//
// Usage (from repository root):
//   swift scripts/generate_cleanup_paths.swift --write
//   swift scripts/generate_cleanup_paths.swift --check

import CryptoKit
import Foundation

// MARK: - Paths

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let engineJSON = repoRoot
    .appendingPathComponent("MacOSCleaner/Resources/engine_paths.json")
let outputSwift = repoRoot
    .appendingPathComponent("MacOSCleaner/Domains/Cleanup/GeneratedCleanupPaths.swift")
let validator = repoRoot.appendingPathComponent("scripts/validate_engine_paths.py")

// MARK: - Category mapping (32 JSON categories → CleanupCategory)

let categoryMap: [String: String] = [
    "browsers": "browserCaches",
    "development": "ideCaches",
    "ai_agents_and_coding": "ideCaches",
    "developer_tools_extended": "ideCaches",
    "communication": "messagingMedia",
    "communication_apps": "messagingMedia",
    "media": "messagingMedia",
    "media_and_creative_tools": "messagingMedia",
    "runtimes_and_package_managers": "languageCaches",
    "devops_and_build_tools": "languageCaches",
    "data_science_and_ml_tools": "languageCaches",
    "database_servers": "languageCaches",
    "ai_models": "dotfileCaches",
    "ai_tools": "dotfileCaches",
    "macos_ai_and_ml": "dotfileCaches",
    "macos_system_caches": "systemCaches",
    "system_mail_and_calendar": "systemCaches",
]

let defaultCategory = "appCaches"

// MARK: - Token → tilde/absolute template for CleanupPath

let tokenReplacements: [(token: String, value: String)] = [
    ("<APP_SUPPORT>", "~/Library/Application Support"),
    ("<CACHES>", "~/Library/Caches"),
    ("<PREFS>", "~/Library/Preferences"),
    ("<CONTAINERS>", "~/Library/Containers"),
    ("<GROUP_CONTAINERS>", "~/Library/Group Containers"),
    ("<LOGS>", "~/Library/Logs"),
    ("<SAVED_STATE>", "~/Library/Saved Application State"),
    ("<USER_LIB>", "~/Library"),
    ("<USER_CONFIG>", "~/.config"),
    ("<USER_CACHE>", "~/.cache"),
    ("<VAR_FOLDERS>", "/private/var/folders"),
    ("<SYS_LIB>", "/Library"),
    ("<SYS_APP_SUPPORT>", "/Library/Application Support"),
    ("<SYS_LAUNCH_AGENTS>", "/Library/LaunchAgents"),
    ("<SYS_LAUNCH_DAEMONS>", "/Library/LaunchDaemons"),
    ("<SYS_PRIV_HELPERS>", "/Library/PrivilegedHelperTools"),
    ("<SYS_CACHES>", "/Library/Caches"),
    ("<SYS_PREFS>", "/Library/Preferences"),
    ("<SYS_LOGS>", "/Library/Logs"),
    ("<HOME>", "~"),
]

// MARK: - JSON models

struct PathRecord: Decodable {
    let p: String
    let purpose: String
    let glob: Bool?
    let system: Bool?
}

struct EntryRecord: Decodable {
    let bundle_ids: [String]?
    let bundle_id_prefixes: [String]?
    let category: String
    let paths: [PathRecord]
}

struct EngineFile: Decodable {
    let version: String
    let apps: [String: EntryRecord]
    let toolchains: [String: EntryRecord]
}

// MARK: - Helpers

func swiftEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func cleanupCategory(for jsonCategory: String) -> String {
    categoryMap[jsonCategory] ?? defaultCategory
}

func purposeCase(_ purpose: String) -> String {
    switch purpose {
    case "cache": ".cache"
    case "app_data": ".appData"
    case "shared": ".shared"
    case "user_content": ".userContent"
    default: ".appData"
    }
}

func tildePath(_ template: String) -> String {
    var result = template
    for (token, value) in tokenReplacements {
        result = result.replacingOccurrences(of: token, with: value)
    }
    return result
}

func requiresSudo(template: String, systemFlag: Bool) -> Bool {
    if systemFlag { return true }
    let expanded = tildePath(template)
    return expanded.hasPrefix("/Library/")
        || expanded.hasPrefix("/private/")
        || expanded.hasPrefix("/usr/local/")
        || expanded.hasPrefix("/opt/homebrew/")
        || expanded.hasPrefix("/var/")
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@discardableResult
func runValidator() throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [validator.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationStatus != 0 {
        fputs(output, stderr)
        return false
    }
    print(output.trimmingCharacters(in: .whitespacesAndNewlines))
    return true
}

// MARK: - Code generation

struct RegistryEntry {
    let key: String
    let bundleIDs: [String]
    let prefixes: [String]
    let category: String
    let paths: [PathRecord]
}

func generateSource(engine: EngineFile, sourceHash: String) -> String {
    var registryEntries: [RegistryEntry] = []
    for (key, entry) in engine.apps.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
        registryEntries.append(RegistryEntry(
            key: key,
            bundleIDs: entry.bundle_ids ?? [],
            prefixes: entry.bundle_id_prefixes ?? [],
            category: cleanupCategory(for: entry.category),
            paths: entry.paths
        ))
    }

    var toolchainEntries: [RegistryEntry] = []
    for (key, entry) in engine.toolchains.sorted(by: { $0.key < $1.key }) {
        toolchainEntries.append(RegistryEntry(
            key: key,
            bundleIDs: [],
            prefixes: [],
            category: cleanupCategory(for: entry.category),
            paths: entry.paths
        ))
    }

    // Cache paths grouped by CleanupCategory (deduped, sorted).
    var cacheByCategory: [String: Set<String>] = [:]
    func ingestCache(_ entry: RegistryEntry) {
        let cat = entry.category
        for path in entry.paths where path.purpose == "cache" {
            let expanded = tildePath(path.p)
            cacheByCategory[cat, default: []].insert(expanded)
        }
    }
    registryEntries.forEach(ingestCache)
    toolchainEntries.forEach(ingestCache)

    // bundle_id → registry key (O(1) lookup).
    var bundleIDToKey: [(bundleID: String, key: String)] = []
    for entry in registryEntries {
        for bid in entry.bundleIDs {
            bundleIDToKey.append((bid.lowercased(), entry.key))
        }
        if entry.bundleIDs.isEmpty {
            bundleIDToKey.append((entry.key.lowercased(), entry.key))
        }
    }
    bundleIDToKey.sort { $0.bundleID < $1.bundleID }

    // Prefix index — longest prefix first at runtime.
    var prefixIndex: [(prefix: String, key: String)] = []
    for entry in registryEntries {
        for prefix in entry.prefixes {
            prefixIndex.append((prefix.lowercased(), entry.key))
        }
    }
    prefixIndex.sort { lhs, rhs in
        if lhs.prefix.count != rhs.prefix.count { return lhs.prefix.count > rhs.prefix.count }
        return lhs.prefix < rhs.prefix
    }

    var lines: [String] = []
    lines.append("// Generated by scripts/generate_cleanup_paths.swift — do not edit.")
    lines.append("// Source: MacOSCleaner/Resources/engine_paths.json")
    lines.append("// SHA-256: \(sourceHash)")
    lines.append("")
    lines.append("import Foundation")
    lines.append("")
    lines.append("public enum PathToken: String, Sendable, CaseIterable {")
    let tokenCases: [(String, String)] = [
        ("appSupport", "<APP_SUPPORT>"),
        ("caches", "<CACHES>"),
        ("prefs", "<PREFS>"),
        ("containers", "<CONTAINERS>"),
        ("groupContainers", "<GROUP_CONTAINERS>"),
        ("logs", "<LOGS>"),
        ("home", "<HOME>"),
        ("savedState", "<SAVED_STATE>"),
        ("userLib", "<USER_LIB>"),
        ("userConfig", "<USER_CONFIG>"),
        ("userCache", "<USER_CACHE>"),
        ("varFolders", "<VAR_FOLDERS>"),
        ("sysLib", "<SYS_LIB>"),
        ("sysAppSupport", "<SYS_APP_SUPPORT>"),
        ("sysLaunchAgents", "<SYS_LAUNCH_AGENTS>"),
        ("sysLaunchDaemons", "<SYS_LAUNCH_DAEMONS>"),
        ("sysPrivHelpers", "<SYS_PRIV_HELPERS>"),
        ("sysCaches", "<SYS_CACHES>"),
        ("sysPrefs", "<SYS_PREFS>"),
        ("sysLogs", "<SYS_LOGS>"),
    ]
    for pair in tokenCases {
        lines.append("    case \(pair.0) = \"\(pair.1)\"")
    }
    lines.append("")
    lines.append("    /// Resolves a tokenized template using the current user home directory.")
    lines.append("    public func resolveTemplate(_ template: String, home: String) -> String {")
    lines.append("        var result = template")
    lines.append("        let replacements: [(PathToken, String)] = [")
    for pair in tokenCases {
        lines.append("            (.\(pair.0), Self.\(pair.0).basePath(home: home)),")
    }
    lines.append("        ]")
    lines.append("        for (token, value) in replacements {")
    lines.append("            result = result.replacingOccurrences(of: token.rawValue, with: value)")
    lines.append("        }")
    lines.append("        return result")
    lines.append("    }")
    lines.append("")
    lines.append("    private func basePath(home: String) -> String {")
    lines.append("        switch self {")
    lines.append("        case .appSupport: return \"\\(home)/Library/Application Support\"")
    lines.append("        case .caches: return \"\\(home)/Library/Caches\"")
    lines.append("        case .prefs: return \"\\(home)/Library/Preferences\"")
    lines.append("        case .containers: return \"\\(home)/Library/Containers\"")
    lines.append("        case .groupContainers: return \"\\(home)/Library/Group Containers\"")
    lines.append("        case .logs: return \"\\(home)/Library/Logs\"")
    lines.append("        case .home: return home")
    lines.append("        case .savedState: return \"\\(home)/Library/Saved Application State\"")
    lines.append("        case .userLib: return \"\\(home)/Library\"")
    lines.append("        case .userConfig: return \"\\(home)/.config\"")
    lines.append("        case .userCache: return \"\\(home)/.cache\"")
    lines.append("        case .varFolders: return \"/private/var/folders\"")
    lines.append("        case .sysLib: return \"/Library\"")
    lines.append("        case .sysAppSupport: return \"/Library/Application Support\"")
    lines.append("        case .sysLaunchAgents: return \"/Library/LaunchAgents\"")
    lines.append("        case .sysLaunchDaemons: return \"/Library/LaunchDaemons\"")
    lines.append("        case .sysPrivHelpers: return \"/Library/PrivilegedHelperTools\"")
    lines.append("        case .sysCaches: return \"/Library/Caches\"")
    lines.append("        case .sysPrefs: return \"/Library/Preferences\"")
    lines.append("        case .sysLogs: return \"/Library/Logs\"")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("public enum PathPurpose: Sendable {")
    lines.append("    case cache")
    lines.append("    case appData")
    lines.append("    case shared")
    lines.append("    case userContent")
    lines.append("}")
    lines.append("")
    lines.append("public struct RegistryPath: Sendable, Equatable {")
    lines.append("    public let template: String")
    lines.append("    public let purpose: PathPurpose")
    lines.append("    public let isGlob: Bool")
    lines.append("    public let requiresAdmin: Bool")
    lines.append("")
    lines.append("    public init(template: String, purpose: PathPurpose, isGlob: Bool = false, requiresAdmin: Bool = false) {")
    lines.append("        self.template = template")
    lines.append("        self.purpose = purpose")
    lines.append("        self.isGlob = isGlob")
    lines.append("        self.requiresAdmin = requiresAdmin")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("public struct AppPaths: Sendable {")
    lines.append("    public let bundleIDs: [String]")
    lines.append("    public let bundleIDPrefixes: [String]")
    lines.append("    public let paths: [RegistryPath]")
    lines.append("    public let category: CleanupCategory")
    lines.append("")
    lines.append("    public init(")
    lines.append("        bundleIDs: [String],")
    lines.append("        bundleIDPrefixes: [String] = [],")
    lines.append("        paths: [RegistryPath],")
    lines.append("        category: CleanupCategory")
    lines.append("    ) {")
    lines.append("        self.bundleIDs = bundleIDs")
    lines.append("        self.bundleIDPrefixes = bundleIDPrefixes")
    lines.append("        self.paths = paths")
    lines.append("        self.category = category")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("public enum GeneratedCleanupPaths {")
    lines.append("")
    lines.append("    public static let sourceHash = \"\(sourceHash)\"")
    lines.append("")

    func emitRegistryBlock(_ name: String, entries: [RegistryEntry]) {
        lines.append("    public static let \(name): [String: AppPaths] = [")
        for entry in entries {
            lines.append("        \"\(swiftEscape(entry.key))\": AppPaths(")
            let bids = entry.bundleIDs.map { "\"\(swiftEscape($0))\"" }.joined(separator: ", ")
            lines.append("            bundleIDs: [\(bids)],")
            let prefixes = entry.prefixes.map { "\"\(swiftEscape($0))\"" }.joined(separator: ", ")
            lines.append("            bundleIDPrefixes: [\(prefixes)],")
            lines.append("            paths: [")
            for path in entry.paths {
                let glob = path.glob ?? false
                let admin = requiresSudo(template: path.p, systemFlag: path.system ?? false)
                var args = "template: \"\(swiftEscape(path.p))\", purpose: \(purposeCase(path.purpose))"
                if glob { args += ", isGlob: true" }
                if admin { args += ", requiresAdmin: true" }
                lines.append("                RegistryPath(\(args)),")
            }
            lines.append("            ],")
            lines.append("            category: .\(entry.category)")
            lines.append("        ),")
        }
        lines.append("    ]")
        lines.append("")
    }

    emitRegistryBlock("registry", entries: registryEntries)
    emitRegistryBlock("toolchains", entries: toolchainEntries)

    lines.append("    public static let bundleIDToRegistryKey: [String: String] = [")
    for pair in bundleIDToKey {
        lines.append("        \"\(swiftEscape(pair.bundleID))\": \"\(swiftEscape(pair.key))\",")
    }
    lines.append("    ]")
    lines.append("")
    lines.append("    public static let prefixIndex: [(prefix: String, key: String)] = [")
    for pair in prefixIndex {
        lines.append("        (prefix: \"\(swiftEscape(pair.prefix))\", key: \"\(swiftEscape(pair.key))\"),")
    }
    lines.append("    ]")
    lines.append("")

    // Cleanup category arrays (cache paths only). Includes all categories that
    // EmbeddedCleanupPaths merges via GeneratedCleanupPaths.cachePaths(for:).
    let legacyCategories = [
        "browserCaches", "ideCaches", "appCaches", "dotfileCaches", "userLogs",
        "messagingMedia", "languageCaches", "systemCaches",
    ]
    for cat in legacyCategories {
        let paths = cacheByCategory[cat, default: []].sorted()
        lines.append("    public static let \(cat): [CleanupPath] = [")
        for path in paths {
            let sudo = path.hasPrefix("/Library/")
                || path.hasPrefix("/private/")
                || path.hasPrefix("/usr/local/")
                || path.hasPrefix("/opt/homebrew/")
                || path.hasPrefix("/var/")
            if sudo {
                lines.append("        CleanupPath(path: \"\(swiftEscape(path))\", category: .\(cat), requiresSudo: true),")
            } else {
                lines.append("        CleanupPath(path: \"\(swiftEscape(path))\", category: .\(cat)),")
            }
        }
        lines.append("    ]")
        lines.append("")
    }

    lines.append("    public static func appPaths(forBundleID bundleID: String) -> AppPaths? {")
    lines.append("        let lower = bundleID.lowercased()")
    lines.append("        guard !lower.isEmpty, !lower.hasPrefix(\"unknown.\") else { return nil }")
    lines.append("        if let key = bundleIDToRegistryKey[lower], let paths = registry[key] { return paths }")
    lines.append("        for entry in prefixIndex where lower.hasPrefix(entry.prefix) {")
    lines.append("            if let paths = registry[entry.key] { return paths }")
    lines.append("        }")
    lines.append("        return nil")
    lines.append("    }")
    lines.append("")
    lines.append("    public static func cachePaths(for category: CleanupCategory) -> [CleanupPath] {")
    lines.append("        paths(for: category)")
    lines.append("    }")
    lines.append("")
    lines.append("    public static func paths(for category: CleanupCategory) -> [CleanupPath] {")
    lines.append("        switch category {")
    for cat in legacyCategories {
        lines.append("        case .\(cat): return \(cat)")
    }
    lines.append("        default: return []")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")

    return lines.joined(separator: "\n")
}

// MARK: - Main

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 1, args[0] == "--write" || args[0] == "--check" else {
        fputs("Usage: swift scripts/generate_cleanup_paths.swift --write|--check\n", stderr)
        exit(2)
    }
    let writeMode = args[0] == "--write"

    guard FileManager.default.fileExists(atPath: engineJSON.path) else {
        fputs("Missing \(engineJSON.path)\n", stderr)
        exit(1)
    }

    guard try runValidator() else {
        fputs("engine_paths.json validation failed\n", stderr)
        exit(1)
    }

    let jsonData = try Data(contentsOf: engineJSON)
    let engine = try JSONDecoder().decode(EngineFile.self, from: jsonData)
    guard engine.version == "3.0" else {
        fputs("Expected engine_paths.json version 3.0, got \(engine.version)\n", stderr)
        exit(1)
    }

    let sourceHash = sha256Hex(jsonData)
    let generated = generateSource(engine: engine, sourceHash: sourceHash)

    if writeMode {
        try generated.write(to: outputSwift, atomically: true, encoding: .utf8)
        print("Wrote \(outputSwift.path)")
    } else {
        let existing = (try? String(contentsOf: outputSwift, encoding: .utf8)) ?? ""
        if existing != generated {
            fputs("GeneratedCleanupPaths.swift is out of date. Run: swift scripts/generate_cleanup_paths.swift --write\n", stderr)
            exit(1)
        }
        print("GeneratedCleanupPaths.swift is up to date.")
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
