import AppIntents
import Foundation

public struct RunScheduledCleanupIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Run Scheduled Cleanup"
    public static let description = IntentDescription("Executes automated non-interactive background cleanup for Automator workflows and macOS schedules.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Dry Run Mode", default: false)
    public var dryRun: Bool

    public init() {
        self.dryRun = false
    }

    public init(dryRun: Bool) {
        self.dryRun = dryRun
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: "settings_cmd_scheduled_cleanup") as? Bool ?? true
        guard (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled else {
            return .result(dialog: "Scheduled Cleanup command is disabled in macOS Cleaner settings.")
        }

        let engine = CleanupEngine()
        // Orphan heuristics are never run unattended — only safe regenerable caches/logs.
        let categoriesToClean: [CleanupCategory] = [.appCaches, .userLogs, .systemCaches, .browserCaches]
        
        let results = (try? await engine.run(categories: categoriesToClean, dryRun: dryRun)) ?? []
        let totalFreedBytes = results.reduce(0) { $0 + $1.freedBytes }

        let mb = Double(totalFreedBytes) / (1024 * 1024)
        let formatted = mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)

        let prefix = dryRun ? "[Preview] Estimated space to free:" : "Scheduled cleanup complete. Freed:"
        return .result(dialog: "\(prefix) \(formatted).")
    }
}
