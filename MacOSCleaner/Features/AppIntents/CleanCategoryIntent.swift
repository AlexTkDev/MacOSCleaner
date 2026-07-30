import AppIntents
import Foundation

public enum CategoryIntentTarget: String, AppEnum, Sendable {
    case appCaches
    case systemCaches
    case userLogs
    case xcode
    case browserCaches
    case orphanedRemnants
    case timeMachineSnapshots
    case largeFiles

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cleanup Category Target"

    public static let caseDisplayRepresentations: [CategoryIntentTarget: DisplayRepresentation] = [
        .appCaches: "Application Caches",
        .systemCaches: "System Caches",
        .userLogs: "User Logs",
        .xcode: "Xcode DerivedData & Caches",
        .browserCaches: "Web Browser Caches",
        .orphanedRemnants: "Orphaned App Remnants",
        .timeMachineSnapshots: "Time Machine Local Snapshots",
        .largeFiles: "Large Files & Archives"
    ]

    var cleanupCategory: CleanupCategory {
        switch self {
        case .appCaches: return .appCaches
        case .systemCaches: return .systemCaches
        case .userLogs: return .userLogs
        case .xcode: return .xcode
        case .browserCaches: return .browserCaches
        case .orphanedRemnants: return .orphanedRemnants
        case .timeMachineSnapshots: return .timeMachineSnapshots
        case .largeFiles: return .largeFiles
        }
    }
}

public struct CleanCategoryIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Clean Specific Category"
    public static let description = IntentDescription("Cleans a specific category of files like caches, logs, or uninstaller leftovers.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Category", default: .userLogs)
    public var category: CategoryIntentTarget

    public init() {
        self.category = .userLogs
    }

    public init(category: CategoryIntentTarget) {
        self.category = category
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: "settings_cmd_clean_category") as? Bool ?? true
        guard (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled else {
            return .result(dialog: "Clean Specific Category command is disabled in macOS Cleaner settings.")
        }

        let engine = CleanupEngine()
        let results = (try? await engine.run(categories: [category.cleanupCategory], dryRun: false)) ?? []
        let freedBytes = results.reduce(0) { $0 + $1.freedBytes }

        let mb = Double(freedBytes) / (1024 * 1024)
        let formatted = mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)

        return .result(dialog: "Cleaned \(category.rawValue). Freed \(formatted).")
    }
}
