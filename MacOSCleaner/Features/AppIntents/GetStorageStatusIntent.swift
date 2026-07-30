import AppIntents
import Foundation

public struct GetStorageStatusIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Get Storage Status"
    public static let description = IntentDescription("Returns current disk storage usage and Trash size.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: "settings_cmd_storage_status") as? Bool ?? true
        guard (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled else {
            return .result(dialog: "Get Storage Status command is disabled in macOS Cleaner settings.")
        }

        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser

        var freeSpace: Int64 = 0
        var totalSpace: Int64 = 0

        if let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            freeSpace = values.volumeAvailableCapacityForImportantUsage ?? 0
            totalSpace = Int64(values.volumeTotalCapacity ?? 0)
        }

        let trashURL = URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash")
        let trashSize = fileManager.getDirectorySize(url: trashURL)

        let freeGB = String(format: "%.1f GB", Double(freeSpace) / (1024 * 1024 * 1024))
        let totalGB = String(format: "%.1f GB", Double(totalSpace) / (1024 * 1024 * 1024))
        let trashMB = Double(trashSize) / (1024 * 1024)
        let trashFormatted = trashMB >= 1024 ? String(format: "%.1f GB", trashMB / 1024) : String(format: "%.0f MB", trashMB)

        let statusMessage = "Storage Status: \(freeGB) free of \(totalGB). Trash size: \(trashFormatted)."
        return .result(dialog: "\(statusMessage)")
    }
}
