import Foundation

public struct CustomSiriCommand: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var phrase: String
    public var categoryRawValue: String
    public var settingKey: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        phrase: String,
        categoryRawValue: String,
        settingKey: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.phrase = phrase
        self.categoryRawValue = categoryRawValue
        self.settingKey = settingKey
        self.isEnabled = isEnabled
    }

    public var displayTitle: String {
        if let settingKey {
            return settingKey.localized
        }
        switch categoryRawValue {
        case "xcode": return "settings_cmd_developer_caches".localized
        case "storage_status": return "settings_cmd_storage_status".localized
        case "systemCaches": return "settings_cmd_clean_category".localized
        case "scheduled_cleanup": return "settings_cmd_scheduled_cleanup".localized
        case "trash": return "settings_cmd_empty_trash".localized
        default: return title.localized
        }
    }

    public var displayPhrase: String {
        switch categoryRawValue {
        case "xcode": return "siri_phrase_developer_caches".localized
        case "storage_status": return "siri_phrase_storage_status".localized
        case "systemCaches": return "siri_phrase_clean_category".localized
        case "scheduled_cleanup": return "siri_phrase_scheduled_cleanup".localized
        case "trash": return "siri_phrase_empty_trash".localized
        default: return phrase.localized
        }
    }

    public static func makeDefaultCommands() -> [CustomSiriCommand] {
        [
            CustomSiriCommand(
                title: "settings_cmd_developer_caches",
                phrase: "siri_phrase_developer_caches",
                categoryRawValue: "xcode",
                settingKey: "settings_cmd_developer_caches",
                isEnabled: UserDefaults.standard.object(forKey: "settings_cmd_developer_caches") as? Bool ?? true
            ),
            CustomSiriCommand(
                title: "settings_cmd_storage_status",
                phrase: "siri_phrase_storage_status",
                categoryRawValue: "storage_status",
                settingKey: "settings_cmd_storage_status",
                isEnabled: UserDefaults.standard.object(forKey: "settings_cmd_storage_status") as? Bool ?? true
            ),
            CustomSiriCommand(
                title: "settings_cmd_clean_category",
                phrase: "siri_phrase_clean_category",
                categoryRawValue: "systemCaches",
                settingKey: "settings_cmd_clean_category",
                isEnabled: UserDefaults.standard.object(forKey: "settings_cmd_clean_category") as? Bool ?? true
            ),
            CustomSiriCommand(
                title: "settings_cmd_scheduled_cleanup",
                phrase: "siri_phrase_scheduled_cleanup",
                categoryRawValue: "scheduled_cleanup",
                settingKey: "settings_cmd_scheduled_cleanup",
                isEnabled: UserDefaults.standard.object(forKey: "settings_cmd_scheduled_cleanup") as? Bool ?? true
            ),
            CustomSiriCommand(
                title: "settings_cmd_empty_trash",
                phrase: "siri_phrase_empty_trash",
                categoryRawValue: "trash",
                settingKey: "settings_cmd_empty_trash",
                isEnabled: UserDefaults.standard.object(forKey: "settings_cmd_empty_trash") as? Bool ?? true
            )
        ]
    }

    /// Snapshot of defaults at first access — prefer `makeDefaultCommands()` for current locale.
    public static var defaultCommands: [CustomSiriCommand] { makeDefaultCommands() }
}
