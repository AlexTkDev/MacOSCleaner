import AppIntents
import Foundation

public struct EmptyTrashIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Empty Trash"
    public static let description = IntentDescription("Safely empties the macOS Trash.")
    public static let openAppWhenRun: Bool = false
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Confirm Deletion", default: true)
    public var confirm: Bool

    @Parameter(title: "Dry Run Mode", default: false)
    public var dryRun: Bool

    public init() {
        self.confirm = true
        self.dryRun = false
    }

    public init(confirm: Bool = true, dryRun: Bool = false) {
        self.confirm = confirm
        self.dryRun = dryRun
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: "settings_cmd_empty_trash") as? Bool ?? true
        guard (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled else {
            return .result(dialog: "Empty Trash command is disabled in macOS Cleaner settings.")
        }

        let isRunningInTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        let shouldDryRun = dryRun || isRunningInTests

        if confirm && !shouldDryRun {
            try await requestConfirmation(
                result: .result(dialog: "Are you sure you want to empty the Trash?")
            )
        }

        let fileManager = FileManager.default
        let trashManager = TrashManager()
        let trashURL = trashManager.trashDirectoryURL
        let items = (try? fileManager.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: [.fileSizeKey, .totalFileSizeKey], options: [])) ?? []

        var freedBytes: Int64 = 0
        for item in items {
            freedBytes += fileManager.getDirectorySize(url: item)
        }

        if !shouldDryRun && !items.isEmpty {
            do {
                freedBytes = try await trashManager.permanentlyDelete(urls: items)
            } catch {
                return .result(dialog: "Could not empty the Trash: \(error.localizedDescription)")
            }
        }

        let mb = Double(freedBytes) / (1024 * 1024)
        let formatted = mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)

        let prefix = shouldDryRun ? "[Preview] Estimated space to free from Trash:" : "Trash emptied. Freed:"
        return .result(dialog: "\(prefix) \(formatted).")
    }
}
