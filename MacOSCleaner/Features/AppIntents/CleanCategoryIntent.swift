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
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Category", default: .userLogs)
    public var category: CategoryIntentTarget

    @Parameter(title: "Confirm Deletion", default: true)
    public var confirm: Bool

    @Parameter(title: "Dry Run Mode", default: false)
    public var dryRun: Bool

    public init() {
        self.category = .userLogs
        self.confirm = true
        self.dryRun = false
    }

    public init(category: CategoryIntentTarget, confirm: Bool = true, dryRun: Bool = false) {
        self.category = category
        self.confirm = confirm
        self.dryRun = dryRun
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: "settings_cmd_clean_category") as? Bool ?? true
        guard (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled else {
            return .result(dialog: "Clean Specific Category command is disabled in macOS Cleaner settings.")
        }

        let isRunningInTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        let shouldDryRun = dryRun || isRunningInTests

        if confirm && !shouldDryRun {
            try await requestConfirmation(
                result: .result(dialog: "Are you sure you want to clean \(category.rawValue)?")
            )
        }

        if category == .largeFiles || category == .orphanedRemnants {
            return .result(dialog: "\(category.rawValue) is review-only. Open macOS Cleaner to choose items.")
        }

        let engine = CleanupEngine()
        let results: [CleanupEngineResult]
        do {
            results = try await engine.run(categories: [category.cleanupCategory], dryRun: shouldDryRun)
        } catch {
            return .result(dialog: "Could not clean \(category.rawValue): \(error.localizedDescription)")
        }
        let freedBytes = results.reduce(0) { $0 + $1.freedBytes }

        let mb = Double(freedBytes) / (1024 * 1024)
        let formatted = mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)

        let prefix = shouldDryRun ? "[Preview] Estimated space to free from \(category.rawValue):" : "Cleaned \(category.rawValue). Freed:"
        return .result(dialog: "\(prefix) \(formatted).")
    }
}
