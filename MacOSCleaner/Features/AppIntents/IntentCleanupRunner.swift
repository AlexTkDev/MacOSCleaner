import Foundation

enum IntentCleanupRunner {
    static var isRunningInTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static func isCommandEnabled(_ key: String) -> Bool {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        return (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled
    }

    static func run(categories: [CleanupCategory], dryRun: Bool) async throws -> Int64 {
        let bypassTrash = UserDefaults.standard.bool(forKey: "bypassTrashOnUninstall")
        let options = CleanupOptions(targetCategories: categories, bypassTrash: bypassTrash)
        if !dryRun {
            _ = await AppQuitter.quit(AppQuitter.cleanupTargets())
        }
        let engine = CleanupEngine()
        let results = try await engine.run(categories: categories, dryRun: dryRun, options: options)
        let totalBytes = results.reduce(Int64(0)) { $0 + $1.freedBytes }
        if !dryRun {
            let mode: OperationRecord.DeletionMode = bypassTrash ? .permanent : .trash
            let ops = results.map { OperationRecord.from(result: $0, deletionMode: mode) }
            let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: ops, trigger: .automatic)
            try? await TransactionJournal().log(transaction: transaction)
        }
        return totalBytes
    }

    static func logTrashTransaction(bytes: Int64) async {
        let op = OperationRecord(
            id: UUID(),
            itemPath: "trash_user_label".localized,
            status: "success",
            bytesFreed: bytes,
            categoryCode: "trash",
            deletionMode: OperationRecord.DeletionMode.permanent.rawValue,
            skipped: 0,
            failed: 0
        )
        let transaction = CleanupTransaction(id: UUID(), timestamp: Date(), operations: [op], trigger: .automatic)
        try? await TransactionJournal().log(transaction: transaction)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
