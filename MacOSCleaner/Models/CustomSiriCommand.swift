import Foundation

public struct CustomSiriCommand: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var phrase: String
    public var categoryRawValue: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        phrase: String,
        categoryRawValue: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.phrase = phrase
        self.categoryRawValue = categoryRawValue
        self.isEnabled = isEnabled
    }

    public var displayTitle: String {
        switch title {
        case "settings_cmd_developer_caches", "Clean Developer Caches (DerivedData, Homebrew, Docker)", "Очистка кэшей разработчика (DerivedData, Homebrew, Docker)":
            return "settings_cmd_developer_caches".localized
        case "settings_cmd_storage_status", "Get Disk Storage Status", "Статус свободного места на диске":
            return "settings_cmd_storage_status".localized
        case "settings_cmd_clean_category", "Clean Specific Category (Caches, Logs, etc.)", "Очистить конкретную категорию (кэши, логи и др.)":
            return "settings_cmd_clean_category".localized
        case "settings_cmd_scheduled_cleanup", "Run Scheduled Cleanup (Automator)", "Запланированная фоновая очистка (Automator)":
            return "settings_cmd_scheduled_cleanup".localized
        default:
            return title.localized
        }
    }

    public var displayPhrase: String {
        switch phrase {
        case "siri_phrase_developer_caches", "Clean developer caches", "Очисти кэши разработчика":
            return "siri_phrase_developer_caches".localized
        case "siri_phrase_storage_status", "How much free space", "Сколько свободного места":
            return "siri_phrase_storage_status".localized
        case "siri_phrase_clean_category", "Clean system caches", "Очисти системные кэши":
            return "siri_phrase_clean_category".localized
        case "siri_phrase_scheduled_cleanup", "Run scheduled cleanup", "Запусти запланированную очистку":
            return "siri_phrase_scheduled_cleanup".localized
        default:
            return phrase.localized
        }
    }

    public static func makeDefaultCommands() -> [CustomSiriCommand] {
        [
            CustomSiriCommand(
                title: "settings_cmd_developer_caches",
                phrase: "siri_phrase_developer_caches",
                categoryRawValue: "xcode",
                isEnabled: true
            ),
            CustomSiriCommand(
                title: "settings_cmd_storage_status",
                phrase: "siri_phrase_storage_status",
                categoryRawValue: "storage_status",
                isEnabled: true
            ),
            CustomSiriCommand(
                title: "settings_cmd_clean_category",
                phrase: "siri_phrase_clean_category",
                categoryRawValue: "systemCaches",
                isEnabled: true
            ),
            CustomSiriCommand(
                title: "settings_cmd_scheduled_cleanup",
                phrase: "siri_phrase_scheduled_cleanup",
                categoryRawValue: "scheduled_cleanup",
                isEnabled: true
            )
        ]
    }

    /// Snapshot of defaults at first access — prefer `makeDefaultCommands()` for current locale.
    public static var defaultCommands: [CustomSiriCommand] { makeDefaultCommands() }
}
