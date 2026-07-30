#!/usr/bin/env swift
// Pack private cleanup catalog asset from engine_paths.json + ui_metadata.json (v3).
//
// Usage (from repository root):
//   swift scripts/generate_cleanup_paths.swift --write
//   swift scripts/generate_cleanup_paths.swift --check
//
// Output (gitignored):
//   MacOSCleaner/Resources/Assets.xcassets/PrivateCleanupCatalog.dataset/

import CryptoKit
import Foundation

// MARK: - Paths

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let engineJSON = repoRoot.appendingPathComponent("MacOSCleaner/Resources/engine_paths.json")
let uiJSON = repoRoot.appendingPathComponent("MacOSCleaner/Resources/ui_metadata.json")
let datasetDir = repoRoot.appendingPathComponent(
    "MacOSCleaner/Resources/Assets.xcassets/PrivateCleanupCatalog.dataset"
)
let catalogBin = datasetDir.appendingPathComponent("catalog.bin")
let contentsJSON = datasetDir.appendingPathComponent("Contents.json")
let validator = repoRoot.appendingPathComponent("scripts/validate_engine_paths.py")

let formatVersion = 1
let magic = Data("MCC1".utf8)
let assetWatermarks: [String] = [
    "com.macos-cleaner.provenance.canary.alpha",
    "com.macos-cleaner.provenance.canary.beta",
    "com.macos-cleaner.provenance.canary.gamma",
    "com.macos-cleaner.provenance.canary.delta",
    "com.macos-cleaner.provenance.canary.epsilon",
    "com.macos-cleaner.provenance.canary.zeta",
    "com.macos-cleaner.provenance.canary.eta",
    "com.macos-cleaner.provenance.canary.theta",
    "com.macos-cleaner.provenance.canary.iota",
    "com.macos-cleaner.provenance.canary.kappa",
    "com.macos-cleaner.provenance.canary.lambda",
    "com.macos-cleaner.provenance.canary.mu",
]

// MARK: - Category mapping (JSON category → CleanupCategory.rawValue)

let categoryMap: [String: String] = [
    "browsers": "browser_caches",
    "development": "ide_caches",
    "ai_agents_and_coding": "ide_caches",
    "developer_tools_extended": "ide_caches",
    "communication": "messaging_media",
    "communication_apps": "messaging_media",
    "media": "messaging_media",
    "media_and_creative_tools": "messaging_media",
    "runtimes_and_package_managers": "language_caches",
    "devops_and_build_tools": "language_caches",
    "data_science_and_ml_tools": "language_caches",
    "database_servers": "language_caches",
    "ai_models": "dotfile_caches",
    "ai_tools": "dotfile_caches",
    "macos_ai_and_ml": "dotfile_caches",
    "macos_system_caches": "system_caches",
    "system_mail_and_calendar": "system_caches",
]
let defaultCategory = "app_caches"

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

struct UIEntryRecord: Decodable {
    let name: String
    let difficulty: String
    let known_issues: [String]
    let bundle_ids: [String]?
    let bundle_id_prefixes: [String]?
    let parent_suite: String?
}

struct UIFile: Decodable {
    let version: String
    let apps: [String: UIEntryRecord]
    let toolchains: [String: UIEntryRecord]?
}

// MARK: - Wire models (must match PrivateCatalogSnapshot.swift)

struct PrivateCatalogWire: Codable, Equatable {
    var formatVersion: Int
    var engineHash: String
    var uiHash: String
    var watermarks: [String]
    var apps: [PrivateCatalogWireApp]
    var toolchains: [PrivateCatalogWireApp]
    var uiApps: [PrivateCatalogWireUI]
    var uiToolchains: [PrivateCatalogWireUI]
}

struct PrivateCatalogWireApp: Codable, Equatable {
    var key: String
    var bundleIDs: [String]
    var bundleIDPrefixes: [String]
    var category: String
    var paths: [PrivateCatalogWirePath]
}

struct PrivateCatalogWirePath: Codable, Equatable {
    var template: String
    var purpose: String
    var isGlob: Bool
    var requiresAdmin: Bool
}

struct PrivateCatalogWireUI: Codable, Equatable {
    var key: String
    var name: String
    var difficulty: String
    var knownIssues: [String]
    var bundleIDs: [String]
    var bundleIDPrefixes: [String]
    var parentSuite: String?
}

// MARK: - Helpers

func tildePath(_ template: String) -> String {
    var result = template
    for (token, value) in tokenReplacements {
        result = result.replacingOccurrences(of: token, with: value)
    }
    return result
}

func requiresAdmin(template: String, systemFlag: Bool) -> Bool {
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

func cleanupCategory(for jsonCategory: String) -> String {
    categoryMap[jsonCategory] ?? defaultCategory
}

func normalizePurpose(_ purpose: String) -> String {
    switch purpose {
    case "cache", "app_data", "shared", "user_content": return purpose
    default: return "app_data"
    }
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

func wireApp(key: String, entry: EntryRecord) -> PrivateCatalogWireApp {
    PrivateCatalogWireApp(
        key: key,
        bundleIDs: entry.bundle_ids ?? [],
        bundleIDPrefixes: entry.bundle_id_prefixes ?? [],
        category: cleanupCategory(for: entry.category),
        paths: entry.paths.map { path in
            PrivateCatalogWirePath(
                template: path.p,
                purpose: normalizePurpose(path.purpose),
                isGlob: path.glob ?? false,
                requiresAdmin: requiresAdmin(template: path.p, systemFlag: path.system ?? false)
            )
        }
    )
}

func wireUI(key: String, entry: UIEntryRecord) -> PrivateCatalogWireUI {
    PrivateCatalogWireUI(
        key: key,
        name: entry.name,
        difficulty: entry.difficulty,
        knownIssues: entry.known_issues,
        bundleIDs: entry.bundle_ids ?? [],
        bundleIDPrefixes: entry.bundle_id_prefixes ?? [],
        parentSuite: entry.parent_suite
    )
}

func buildWire(engine: EngineFile, ui: UIFile, engineHash: String, uiHash: String) -> PrivateCatalogWire {
    let apps = engine.apps.keys.sorted { $0.lowercased() < $1.lowercased() }.map { key in
        wireApp(key: key, entry: engine.apps[key]!)
    }
    let toolchains = engine.toolchains.keys.sorted().map { key in
        wireApp(key: key, entry: engine.toolchains[key]!)
    }
    let uiApps = ui.apps.keys.sorted { $0.lowercased() < $1.lowercased() }.map { key in
        wireUI(key: key, entry: ui.apps[key]!)
    }
    let uiToolchains = (ui.toolchains ?? [:]).keys.sorted().map { key in
        wireUI(key: key, entry: ui.toolchains![key]!)
    }
    return PrivateCatalogWire(
        formatVersion: formatVersion,
        engineHash: engineHash,
        uiHash: uiHash,
        watermarks: assetWatermarks,
        apps: apps,
        toolchains: toolchains,
        uiApps: uiApps,
        uiToolchains: uiToolchains
    )
}

func encodeAsset(_ wire: PrivateCatalogWire) throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let plist = try encoder.encode(wire)
    let compressed = try (plist as NSData).compressed(using: .zlib) as Data
    var output = magic
    output.append(compressed)
    return output
}

func decodeAsset(_ data: Data) throws -> PrivateCatalogWire {
    guard data.count > magic.count, data.prefix(magic.count) == magic else {
        throw NSError(domain: "PrivateCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid magic"])
    }
    let compressed = data.dropFirst(magic.count)
    let plist = try (compressed as NSData).decompressed(using: .zlib) as Data
    return try PropertyListDecoder().decode(PrivateCatalogWire.self, from: plist)
}

func datasetContentsJSON() -> String {
    """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "data" : [
        {
          "idiom" : "universal",
          "filename" : "catalog.bin",
          "universal-type-identifier" : "public.data"
        }
      ]
    }
    """
}

func writeDataset(_ assetData: Data) throws {
    try FileManager.default.createDirectory(at: datasetDir, withIntermediateDirectories: true)
    try assetData.write(to: catalogBin, options: .atomic)
    try datasetContentsJSON().write(to: contentsJSON, atomically: true, encoding: .utf8)
}

// MARK: - Main

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 1, args[0] == "--write" || args[0] == "--check" else {
        fputs("Usage: swift scripts/generate_cleanup_paths.swift --write|--check\n", stderr)
        exit(2)
    }
    let writeMode = args[0] == "--write"

    let fm = FileManager.default
    let engineExists = fm.fileExists(atPath: engineJSON.path)
    let uiExists = fm.fileExists(atPath: uiJSON.path)

    if !engineExists && !uiExists {
        if writeMode {
            fputs("Missing engine_paths.json and ui_metadata.json — nothing to pack.\n", stderr)
            exit(1)
        }
        print("Private catalog SoT absent — public build OK (skip check).")
        exit(0)
    }
    if engineExists != uiExists {
        fputs("Both engine_paths.json and ui_metadata.json are required together.\n", stderr)
        exit(1)
    }

    guard try runValidator() else {
        fputs("engine_paths.json / ui_metadata.json validation failed\n", stderr)
        exit(1)
    }

    let engineData = try Data(contentsOf: engineJSON)
    let uiData = try Data(contentsOf: uiJSON)
    let engine = try JSONDecoder().decode(EngineFile.self, from: engineData)
    let ui = try JSONDecoder().decode(UIFile.self, from: uiData)
    guard engine.version == "3.0", ui.version == "3.0" else {
        fputs("Expected version 3.0 in both JSON files\n", stderr)
        exit(1)
    }

    let engineHash = sha256Hex(engineData)
    let uiHash = sha256Hex(uiData)
    let expected = buildWire(engine: engine, ui: ui, engineHash: engineHash, uiHash: uiHash)
    let assetData = try encodeAsset(expected)

    if writeMode {
        try writeDataset(assetData)
        print("Wrote \(catalogBin.path) (\(assetData.count) bytes, apps=\(expected.apps.count), toolchains=\(expected.toolchains.count))")
        exit(0)
    }

    guard fm.fileExists(atPath: catalogBin.path) else {
        fputs("Private catalog asset missing. Run: swift scripts/generate_cleanup_paths.swift --write\n", stderr)
        exit(1)
    }
    let existingData = try Data(contentsOf: catalogBin)
    let decoded = try decodeAsset(existingData)
    if decoded != expected {
        fputs("Private catalog asset is out of date. Run: swift scripts/generate_cleanup_paths.swift --write\n", stderr)
        exit(1)
    }
    print("PrivateCleanupCatalog.dataset is up to date.")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
