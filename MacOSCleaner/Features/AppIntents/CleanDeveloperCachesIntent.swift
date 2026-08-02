import AppIntents
import Foundation

public enum DeveloperCacheTarget: String, AppEnum, Sendable {
    case all
    case xcode
    case packageManagers
    case docker

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Developer Cache Target"

    public static let caseDisplayRepresentations: [DeveloperCacheTarget: DisplayRepresentation] = [
        .all: "All Developer Caches",
        .xcode: "Xcode DerivedData & Caches",
        .packageManagers: "Package Managers (Homebrew/npm/CocoaPods)",
        .docker: "Docker Virtual Images & Containers"
    ]
}

public struct CleanDeveloperCachesIntent: AppIntent, Sendable {
    public static let title: LocalizedStringResource = "Clean Developer Caches"
    public static let description = IntentDescription("Cleans Xcode DerivedData, Homebrew, package managers, and Docker caches.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Target Component", default: .all)
    public var target: DeveloperCacheTarget

    public init() {
        self.target = .all
    }

    public init(target: DeveloperCacheTarget) {
        self.target = target
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: "settings_cmd_developer_caches") as? Bool ?? true
        guard (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled else {
            return .result(dialog: "Clean Developer Caches command is disabled in macOS Cleaner settings.")
        }

        let engine = CleanupEngine()
        var freedBytes: Int64 = 0

        switch target {
        case .all:
            let results = (try? await engine.run(categories: [.xcode, .packageManagers, .docker], dryRun: false)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        case .xcode:
            let results = (try? await engine.run(categories: [.xcode], dryRun: false)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        case .packageManagers:
            let results = (try? await engine.run(categories: [.packageManagers], dryRun: false)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        case .docker:
            let results = (try? await engine.run(categories: [.docker], dryRun: false)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        }

        let mb = Double(freedBytes) / (1024 * 1024)
        let formatted = mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)

        return .result(dialog: "Successfully cleaned developer caches (\(target.rawValue)). Freed \(formatted).")
    }
}
