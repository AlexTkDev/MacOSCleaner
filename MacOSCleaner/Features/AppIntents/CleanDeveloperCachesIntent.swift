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

    @Parameter(title: "Confirm Deletion", default: true)
    public var confirm: Bool

    @Parameter(title: "Dry Run Mode", default: false)
    public var dryRun: Bool

    public init() {
        self.target = .all
        self.confirm = true
        self.dryRun = false
    }

    public init(target: DeveloperCacheTarget, confirm: Bool = true, dryRun: Bool = false) {
        self.target = target
        self.confirm = confirm
        self.dryRun = dryRun
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard IntentCleanupRunner.isCommandEnabled("settings_cmd_developer_caches") else {
            return .result(dialog: "Clean Developer Caches command is disabled in macOS Cleaner settings.")
        }

        let shouldDryRun = dryRun || IntentCleanupRunner.isRunningInTests

        let categories: [CleanupCategory] = {
            switch target {
            case .all:
                return [
                    .xcode, .iosSimulators, .packageManagers, .gradleMaven,
                    .flutterDart, .androidCaches, .androidSDK, .ideCaches,
                    .languageCaches, .swiftPMCache, .carthageCache, .docker,
                ]
            case .xcode: return [.xcode]
            case .packageManagers: return [.packageManagers]
            case .docker: return [.docker]
            }
        }()

        if shouldDryRun {
            let freedBytes: Int64
            do {
                freedBytes = try await IntentCleanupRunner.run(categories: categories, dryRun: true)
            } catch {
                return .result(dialog: "Could not preview developer caches: \(error.localizedDescription)")
            }
            let formatted = IntentCleanupRunner.formatBytes(freedBytes)
            return .result(dialog: "[Preview] Estimated space to free from developer caches (\(target.rawValue)): \(formatted).")
        }

        if confirm {
            let previewBytes: Int64
            do {
                previewBytes = try await IntentCleanupRunner.run(categories: categories, dryRun: true)
            } catch {
                return .result(dialog: "Could not preview developer caches: \(error.localizedDescription)")
            }
            let formatted = IntentCleanupRunner.formatBytes(previewBytes)
            try await requestConfirmation(
                dialog: "Found \(formatted) of developer caches (\(target.rawValue)). Do you want to clean?"
            )
        }

        let freedBytes: Int64
        do {
            freedBytes = try await IntentCleanupRunner.run(categories: categories, dryRun: false)
        } catch {
            return .result(dialog: "Could not clean developer caches: \(error.localizedDescription)")
        }
        let formatted = IntentCleanupRunner.formatBytes(freedBytes)
        return .result(dialog: "Successfully cleaned developer caches (\(target.rawValue)). Freed: \(formatted).")
    }
}
