import AppIntents
import Foundation

public struct RunScheduledCleanupIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Run Scheduled Cleanup"
    public static let description = IntentDescription("Executes automated non-interactive background cleanup for Automator workflows and macOS schedules.")
    public static let openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Dry Run Mode", default: false)
    public var dryRun: Bool

    public init() {
        self.dryRun = false
    }

    public init(dryRun: Bool) {
        self.dryRun = dryRun
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard IntentCleanupRunner.isCommandEnabled("settings_cmd_scheduled_cleanup") else {
            return .result(dialog: "Scheduled Cleanup command is disabled in macOS Cleaner settings.")
        }

        let shouldDryRun = dryRun || IntentCleanupRunner.isRunningInTests
        // Orphan heuristics are never run unattended — only safe regenerable caches/logs.
        let categoriesToClean: [CleanupCategory] = [.appCaches, .userLogs, .systemCaches, .browserCaches]

        let totalFreedBytes: Int64
        do {
            totalFreedBytes = try await IntentCleanupRunner.run(categories: categoriesToClean, dryRun: shouldDryRun)
        } catch {
            return .result(dialog: "Scheduled cleanup failed: \(error.localizedDescription)")
        }

        let formatted = IntentCleanupRunner.formatBytes(totalFreedBytes)
        let prefix = shouldDryRun ? "[Preview] Estimated space to free:" : "Scheduled cleanup complete. Freed:"
        return .result(dialog: "\(prefix) \(formatted).")
    }
}
