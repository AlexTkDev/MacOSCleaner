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

    public static let defaultCommands: [CustomSiriCommand] = [
        CustomSiriCommand(
            title: "settings_cmd_developer_caches".localized,
            phrase: "Очисти кэши разработчика",
            categoryRawValue: "xcode",
            isEnabled: true
        ),
        CustomSiriCommand(
            title: "settings_cmd_storage_status".localized,
            phrase: "Сколько свободного места",
            categoryRawValue: "storage_status",
            isEnabled: true
        ),
        CustomSiriCommand(
            title: "settings_cmd_clean_category".localized,
            phrase: "Очисти системные кэши",
            categoryRawValue: "systemCaches",
            isEnabled: true
        ),
        CustomSiriCommand(
            title: "settings_cmd_scheduled_cleanup".localized,
            phrase: "Запусти запланированную очистку",
            categoryRawValue: "scheduled_cleanup",
            isEnabled: true
        )
    ]
}
