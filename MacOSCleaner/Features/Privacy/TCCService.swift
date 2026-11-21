import AppKit
import Foundation
import OSLog
import SQLite3

private extension Logger {
    static let tcc = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "TCCService"
    )
}

public struct TCCAppPermissionSummary: Sendable, Equatable {
    public let entries: [TCCPermissionEntry]
    public let userDBStatus: TCCDatabaseStatus

    public var count: Int { entries.count }
    public var allowedCount: Int { entries.filter { $0.authStatus == .allowed || $0.authStatus == .limited }.count }
    public var deniedCount: Int { entries.filter { $0.authStatus == .denied }.count }
    public var requiresFDA: Bool {
        if case .requiresFullDiskAccess = userDBStatus { return true }
        return false
    }
}

public enum TCCResetError: Error, LocalizedError, Equatable {
    case invalidBundleID(String)
    case unsupportedService(String)
    case entryNotFound(String)
    case executionFailed(String)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBundleID(let id):
            return String(format: "privacy_tcc_error_invalid_bundle".localized, id)
        case .unsupportedService(let service):
            return String(format: "privacy_tcc_error_unsupported_service".localized, service)
        case .entryNotFound(let id):
            return String(format: "privacy_tcc_error_entry_not_found".localized, id)
        case .executionFailed(let message):
            return String(format: "privacy_tcc_error_reset_failed".localized, message)
        case .verificationFailed(let message):
            return String(format: "privacy_tcc_error_verify_failed".localized, message)
        }
    }
}

public actor TCCService {
    private let commandRunner: any CommandRunning
    private let fileManager: FileManager
    private let userDBPath: String
    private let systemDBPath: String
    private let hasFullDiskAccessProvider: @Sendable () -> Bool

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        fileManager: FileManager = .default,
        userDBPath: String = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
        systemDBPath: String = "/Library/Application Support/com.apple.TCC/TCC.db",
        hasFullDiskAccessProvider: @escaping @Sendable () -> Bool = { PermissionsManager.checkFullDiskAccess() }
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.userDBPath = userDBPath
        self.systemDBPath = systemDBPath
        self.hasFullDiskAccessProvider = hasFullDiskAccessProvider
    }

    // MARK: - Snapshot & Count

    public func loadSnapshot() async -> TCCSnapshot {
        let userResult = Self.readDatabase(
            at: userDBPath,
            scope: .user,
            hasFDA: hasFullDiskAccessProvider(),
            fileManager: fileManager
        )
        let systemResult = Self.readDatabase(
            at: systemDBPath,
            scope: .system,
            hasFDA: true,
            fileManager: fileManager
        )

        let allEntries = userResult.entries + systemResult.entries
        let grouped = Dictionary(grouping: allEntries, by: \.client)

        let bundleIndex = await buildBundleURLIndex(for: Set(grouped.keys))
        let runningBundleIDs = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }

        let identities = await resolveIdentities(for: bundleIndex)

        var groups: [TCCAppGroup] = []
        groups.reserveCapacity(grouped.count)

        for (client, entries) in grouped {
            let sortedEntries = entries.sorted {
                if $0.service.localizedTitle != $1.service.localizedTitle {
                    return $0.service.localizedTitle.localizedCaseInsensitiveCompare($1.service.localizedTitle) == .orderedAscending
                }
                return $0.scope.rawValue < $1.scope.rawValue
            }
            let identity = identities[client]
            let appURL = bundleIndex[client] ?? identity?.bundleURL
            let appName = identity?.bundleName
                ?? identity?.appName
                ?? appURL.map { $0.deletingPathExtension().lastPathComponent }
                ?? client

            groups.append(TCCAppGroup(
                client: client,
                appName: appName,
                appURL: appURL,
                appIdentity: identity,
                isRunning: runningBundleIDs.contains(client),
                entries: sortedEntries
            ))
        }

        groups.sort { lhs, rhs in
            lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }

        return TCCSnapshot(
            userDBStatus: userResult.status,
            systemDBStatus: systemResult.status,
            groups: groups,
            totalEntryCount: allEntries.count
        )
    }

    /// Lightweight summary for Uninstaller app header without resolving full AppIdentity graph.
    public func permissionSummary(forBundleID bundleID: String) -> TCCAppPermissionSummary {
        let userResult = Self.readDatabase(
            at: userDBPath,
            scope: .user,
            hasFDA: hasFullDiskAccessProvider(),
            fileManager: fileManager
        )
        let systemResult = Self.readDatabase(
            at: systemDBPath,
            scope: .system,
            hasFDA: true,
            fileManager: fileManager
        )
        let matching = (userResult.entries + systemResult.entries)
            .filter { $0.client.caseInsensitiveCompare(bundleID) == .orderedSame }
            .sorted { lhs, rhs in
                let lhsRank = Self.statusSortRank(lhs.authStatus)
                let rhsRank = Self.statusSortRank(rhs.authStatus)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.service.localizedTitle.localizedCaseInsensitiveCompare(rhs.service.localizedTitle) == .orderedAscending
            }
        return TCCAppPermissionSummary(entries: matching, userDBStatus: userResult.status)
    }

    private static func statusSortRank(_ status: TCCAuthStatus) -> Int {
        switch status {
        case .allowed: return 0
        case .limited: return 1
        case .denied: return 2
        case .unknown: return 3
        }
    }

    /// Lightweight count for Uninstaller app header without resolving full AppIdentity graph.
    public func permissionCount(forBundleID bundleID: String) -> (count: Int, requiresFDA: Bool) {
        let summary = permissionSummary(forBundleID: bundleID)
        return (summary.count, summary.requiresFDA)
    }

    // MARK: - Reset & Verification

    public func resetPermission(_ entry: TCCPermissionEntry) async throws -> TCCSnapshot {
        guard Self.isValidBundleID(entry.client) else {
            throw TCCResetError.invalidBundleID(entry.client)
        }
        guard entry.isResettable, let serviceToken = entry.service.tccutilName else {
            throw TCCResetError.unsupportedService(entry.service.localizedTitle)
        }

        let before = await loadSnapshot()
        let exists = before.groups
            .flatMap(\.entries)
            .contains { $0.id == entry.id }
        guard exists else {
            throw TCCResetError.entryNotFound(entry.client)
        }

        let result = try await commandRunner.run(
            command: "/usr/bin/tccutil",
            arguments: ["reset", serviceToken, entry.client],
            timeout: .seconds(10)
        )

        if result.exitCode != 0 {
            let errText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = errText.isEmpty ? "exit \(result.exitCode)" : errText
            Logger.tcc.error("tccutil reset failed for \(entry.client, privacy: .public): \(msg, privacy: .public)")
            throw TCCResetError.executionFailed(msg)
        }

        let after = await loadSnapshot()
        let stillActive = after.groups
            .flatMap(\.entries)
            .contains { $0.id == entry.id && $0.authStatus != .denied }
        if stillActive {
            throw TCCResetError.verificationFailed(entry.service.localizedTitle)
        }

        Logger.tcc.info("Reset TCC \(serviceToken, privacy: .public) for \(entry.client, privacy: .public)")
        return after
    }

    public func resetAllPermissions(for group: TCCAppGroup) async throws -> TCCSnapshot {
        guard Self.isValidBundleID(group.client) else {
            throw TCCResetError.invalidBundleID(group.client)
        }

        let resettable = group.entries.filter(\.isResettable)
        guard !resettable.isEmpty else {
            throw TCCResetError.unsupportedService(group.appName)
        }

        let before = await loadSnapshot()
        let exists = before.groups.contains { $0.client == group.client && $0.hasResettableEntries }
        guard exists else {
            throw TCCResetError.entryNotFound(group.client)
        }

        let result = try await commandRunner.run(
            command: "/usr/bin/tccutil",
            arguments: ["reset", "All", group.client],
            timeout: .seconds(10)
        )

        if result.exitCode != 0 {
            let errText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = errText.isEmpty ? "exit \(result.exitCode)" : errText
            Logger.tcc.error("tccutil reset All failed for \(group.client, privacy: .public): \(msg, privacy: .public)")
            throw TCCResetError.executionFailed(msg)
        }

        let after = await loadSnapshot()
        let remaining = after.groups
            .first(where: { $0.client == group.client })?
            .entries
            .filter { $0.isResettable && $0.authStatus != .denied } ?? []
        if !remaining.isEmpty {
            let names = remaining.map(\.service.localizedTitle).joined(separator: ", ")
            throw TCCResetError.verificationFailed(names)
        }

        Logger.tcc.info("Reset all user TCC permissions for \(group.client, privacy: .public)")
        return after
    }

    // MARK: - Validation

    public static func isValidBundleID(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty, bundleID.count <= 255 else { return false }
        guard !bundleID.hasPrefix("."), !bundleID.hasSuffix("."), !bundleID.contains("..") else {
            return false
        }
        return bundleID.wholeMatch(of: /^[A-Za-z0-9.-]+$/) != nil
    }

    // MARK: - Read-only SQLite Reader (Defensive Schema Parsing)

    struct DBReadResult: Sendable {
        let status: TCCDatabaseStatus
        let entries: [TCCPermissionEntry]
    }

    static func readDatabase(
        at path: String,
        scope: TCCDatabaseScope,
        hasFDA: Bool,
        fileManager: FileManager = .default
    ) -> DBReadResult {
        if scope == .user && !hasFDA {
            return DBReadResult(status: .requiresFullDiskAccess, entries: [])
        }

        guard fileManager.fileExists(atPath: path) else {
            if scope == .system {
                return DBReadResult(status: .sipProtected, entries: [])
            }
            return DBReadResult(status: .unavailable(reason: "privacy_tcc_db_missing".localized), entries: [])
        }

        let fileURI = URL(fileURLWithPath: path).absoluteString + "?mode=ro&immutable=1"
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let rc = sqlite3_open_v2(fileURI, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let errCode = rc
            if let db { sqlite3_close(db) }
            if scope == .system {
                return DBReadResult(status: .sipProtected, entries: [])
            }
            if errCode == SQLITE_PERM || errCode == SQLITE_CANTOPEN {
                return DBReadResult(status: .requiresFullDiskAccess, entries: [])
            }
            return DBReadResult(status: .unavailable(reason: "SQLite (\(errCode))"), entries: [])
        }
        defer { sqlite3_close(db) }

        let columns = fetchAccessColumns(db: db)
        guard columns.contains("service"), columns.contains("client") else {
            // Either SIP-blocked read (zero rows/tables readable) or unexpected schema.
            if scope == .system && columns.isEmpty {
                return DBReadResult(status: .sipProtected, entries: [])
            }
            return DBReadResult(status: .unavailable(reason: "privacy_tcc_schema_unsupported".localized), entries: [])
        }

        let hasClientType = columns.contains("client_type")
        let hasAuthValue = columns.contains("auth_value")
        let hasAllowed = columns.contains("allowed")
        let hasAuthReason = columns.contains("auth_reason")
        let hasLastModified = columns.contains("last_modified")

        var selectedColumns = ["service", "client"]
        if hasClientType { selectedColumns.append("client_type") }
        if hasAuthValue { selectedColumns.append("auth_value") }
        if hasAllowed { selectedColumns.append("allowed") }
        if hasAuthReason { selectedColumns.append("auth_reason") }
        if hasLastModified { selectedColumns.append("last_modified") }

        let sql = "SELECT \(selectedColumns.joined(separator: ", ")) FROM access;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            if scope == .system {
                return DBReadResult(status: .sipProtected, entries: [])
            }
            return DBReadResult(status: .unavailable(reason: msg), entries: [])
        }
        defer { sqlite3_finalize(stmt) }

        let colIndex = Dictionary(uniqueKeysWithValues: selectedColumns.enumerated().map { ($0.element, Int32($0.offset)) })
        var entries: [TCCPermissionEntry] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let rawServicePtr = sqlite3_column_text(stmt, colIndex["service"] ?? 0),
                  let rawClientPtr = sqlite3_column_text(stmt, colIndex["client"] ?? 1) else {
                continue
            }
            let rawService = String(cString: rawServicePtr)
            let client = String(cString: rawClientPtr)
            guard !rawService.isEmpty, !client.isEmpty else { continue }

            let clientType = colIndex["client_type"].map { Int(sqlite3_column_int(stmt, $0)) } ?? 0

            let authStatus: TCCAuthStatus
            if let idx = colIndex["auth_value"] {
                let val = Int(sqlite3_column_int(stmt, idx))
                switch val {
                case 0: authStatus = .denied
                case 2: authStatus = .allowed
                case 3: authStatus = .limited
                default: authStatus = .unknown(val)
                }
            } else if let idx = colIndex["allowed"] {
                let val = Int(sqlite3_column_int(stmt, idx))
                authStatus = val == 1 ? .allowed : .denied
            } else {
                authStatus = .unknown(-1)
            }

            let authReason: Int? = colIndex["auth_reason"].flatMap { idx in
                sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, idx))
            }

            let lastModified: Date? = colIndex["last_modified"].flatMap { idx in
                guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
                let ts = sqlite3_column_int64(stmt, idx)
                return ts > 0 ? Date(timeIntervalSince1970: TimeInterval(ts)) : nil
            }

            entries.append(TCCPermissionEntry(
                service: TCCPermissionService(rawService: rawService),
                client: client,
                clientType: clientType,
                authStatus: authStatus,
                authReason: authReason,
                lastModified: lastModified,
                scope: scope
            ))
        }

        return DBReadResult(status: .available(path: path), entries: entries)
    }

    private static func fetchAccessColumns(db: OpaquePointer) -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(access);", -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var cols = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 1) {
                cols.insert(String(cString: namePtr))
            }
        }
        return cols
    }

    // MARK: - AppIdentity Matching

    private func buildBundleURLIndex(for clients: Set<String>) async -> [String: URL] {
        var map: [String: URL] = [:]
        var unresolved = Set<String>()

        for client in clients where Self.isValidBundleID(client) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) {
                map[client] = url
            } else {
                unresolved.insert(client)
            }
        }

        if !unresolved.isEmpty {
            let discovered = await AppDiscovery(commandRunner: (commandRunner as? CommandRunner) ?? CommandRunner()).findAll()
            for url in discovered {
                guard let id = Bundle(url: url)?.bundleIdentifier,
                      unresolved.contains(id),
                      map[id] == nil else { continue }
                map[id] = url
            }
        }
        return map
    }

    private struct BundleEntry: Sendable {
        let bundleID: String
        let url: URL
    }

    private struct ResolvedIdentity: Sendable {
        let bundleID: String
        let identity: AppIdentity
    }

    private func resolveIdentities(for bundleIndex: [String: URL]) async -> [String: AppIdentity] {
        let runner = (commandRunner as? CommandRunner) ?? CommandRunner()
        let entries = bundleIndex.map { BundleEntry(bundleID: $0.key, url: $0.value) }
        let resolved: [ResolvedIdentity] = (try? await UninstallerService.mapWithBoundedConcurrency(
            items: entries,
            maxConcurrent: UninstallerService.maxConcurrentDiscoveryTasks
        ) { entry in
            let identity = await AppIdentity.resolve(from: entry.url, commandRunner: runner)
            return ResolvedIdentity(bundleID: entry.bundleID, identity: identity)
        }) ?? []
        return Dictionary(uniqueKeysWithValues: resolved.map { ($0.bundleID, $0.identity) })
    }
}
