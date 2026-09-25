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
    public static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Target Component", default: .all)
    public var target: DeveloperCacheTarget

    @Parameter(title: "Confirm Deletion", default: false)
    public var confirm: Bool

    @Parameter(title: "Dry Run Mode", default: false)
    public var dryRun: Bool

    public init() {
        self.target = .all
        self.confirm = false
        self.dryRun = false
    }

    public init(target: DeveloperCacheTarget, confirm: Bool = false, dryRun: Bool = false) {
        self.target = target
        self.confirm = confirm
        self.dryRun = dryRun
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let isShortcutsEnabled = UserDefaults.standard.object(forKey: "settings_enableShortcutsAndAutomator") as? Bool ?? true
        let isSiriEnabled = UserDefaults.standard.object(forKey: "settings_enableSiri") as? Bool ?? true
        let isCommandEnabled = UserDefaults.standard.object(forKey: "settings_cmd_developer_caches") as? Bool ?? true
        guard (isShortcutsEnabled || isSiriEnabled) && isCommandEnabled else {
            return .result(dialog: "Clean Developer Caches command is disabled in macOS Cleaner settings.")
        }

        let isRunningInTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        let shouldDryRun = dryRun || isRunningInTests

        if confirm && !shouldDryRun {
            try await requestConfirmation(
                result: .result(dialog: "Are you sure you want to clean developer caches (\(target.rawValue))?")
            )
        }

        let engine = CleanupEngine()
        var freedBytes: Int64 = 0

        switch target {
        case .all:
            let results = (try? await engine.run(categories: [.xcode, .packageManagers, .docker], dryRun: shouldDryRun)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        case .xcode:
            let results = (try? await engine.run(categories: [.xcode], dryRun: shouldDryRun)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        case .packageManagers:
            let results = (try? await engine.run(categories: [.packageManagers], dryRun: shouldDryRun)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        case .docker:
            let results = (try? await engine.run(categories: [.docker], dryRun: shouldDryRun)) ?? []
            freedBytes = results.reduce(0) { $0 + $1.freedBytes }
        }

        let mb = Double(freedBytes) / (1024 * 1024)
        let formatted = mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)

        let prefix = shouldDryRun ? "[Preview] Estimated space to free from developer caches (\(target.rawValue)):" : "Successfully cleaned developer caches (\(target.rawValue)). Freed:"
        return .result(dialog: "\(prefix) \(formatted).")
    }
}
