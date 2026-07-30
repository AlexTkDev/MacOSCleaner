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

    public static func makeDefaultCommands() -> [CustomSiriCommand] {
        [
            CustomSiriCommand(
                title: "settings_cmd_developer_caches".localized,
                phrase: "siri_phrase_developer_caches".localized,
                categoryRawValue: "xcode",
                isEnabled: true
            ),
            CustomSiriCommand(
                title: "settings_cmd_storage_status".localized,
                phrase: "siri_phrase_storage_status".localized,
                categoryRawValue: "storage_status",
                isEnabled: true
            ),
            CustomSiriCommand(
                title: "settings_cmd_clean_category".localized,
                phrase: "siri_phrase_clean_category".localized,
                categoryRawValue: "systemCaches",
                isEnabled: true
            ),
            CustomSiriCommand(
                title: "settings_cmd_scheduled_cleanup".localized,
                phrase: "siri_phrase_scheduled_cleanup".localized,
                categoryRawValue: "scheduled_cleanup",
                isEnabled: true
            )
        ]
    }

    /// Snapshot of defaults at first access — prefer `makeDefaultCommands()` for current locale.
    public static var defaultCommands: [CustomSiriCommand] { makeDefaultCommands() }
}
