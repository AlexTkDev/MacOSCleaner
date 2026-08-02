import SwiftUI

public struct CustomSiriCommandEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    var commandToEdit: CustomSiriCommand?
    var onSave: (CustomSiriCommand) -> Void

    @State private var title: String = ""
    @State private var phrase: String = ""
    @State private var selectedCategory: String = "userLogs"

    var availableCategories: [(key: String, label: String)] {
        [
            ("userLogs", "settings_cmd_category_user_logs".localized),
            ("appCaches", "settings_cmd_category_app_caches".localized),
            ("systemCaches", "settings_cmd_category_system_caches".localized),
            ("xcode", "settings_cmd_developer_caches".localized),
            ("browserCaches", "settings_cmd_category_browser_caches".localized),
            ("orphanedRemnants", "settings_cmd_category_orphaned_remnants".localized),
            ("storage_status", "settings_cmd_storage_status".localized),
            ("scheduled_cleanup", "settings_cmd_scheduled_cleanup".localized)
        ]
    }

    public init(
        commandToEdit: CustomSiriCommand? = nil,
        onSave: @escaping (CustomSiriCommand) -> Void
    ) {
        self.commandToEdit = commandToEdit
        self.onSave = onSave
        _title = State(initialValue: commandToEdit?.displayTitle ?? "")
        _phrase = State(initialValue: commandToEdit?.displayPhrase ?? "")
        _selectedCategory = State(initialValue: commandToEdit?.categoryRawValue ?? "userLogs")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(commandToEdit == nil ? "siri_add_command_title".localized : "siri_edit_command_title".localized)
                .font(.headline)

            Form {
                TextField("siri_command_name_label".localized, text: $title)
                TextField("siri_command_phrase_label".localized, text: $phrase)

                Picker("siri_command_category_label".localized, selection: $selectedCategory) {
                    ForEach(availableCategories, id: \.key) { cat in
                        Text(cat.label).tag(cat.key)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("cancel_action".localized) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("save_action".localized) {
                    let cmd = CustomSiriCommand(
                        id: commandToEdit?.id ?? UUID(),
                        title: title.isEmpty ? "siri_new_command_default".localized : title,
                        phrase: phrase,
                        categoryRawValue: selectedCategory,
                        isEnabled: commandToEdit?.isEnabled ?? true
                    )
                    onSave(cmd)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 280)
    }
}
