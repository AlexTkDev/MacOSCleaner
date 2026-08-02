import SwiftUI

struct SettingsProcessesView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                processesCard
            }
            .padding(20)
        }
    }

    private var processesCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_processes_title".localized, subtitle: "settings_processes_sub".localized, iconName: "cpu", iconColor: .orange)
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsLabeledControl(
                        "settings_refresh_interval".localized,
                        subtitle: "settings_refresh_interval_sub".localized
                    ) {
                        Picker("", selection: $settings.processRefreshInterval) {
                            ForEach(RefreshInterval.allCases) { interval in
                                Text(interval.localizedName).tag(interval)
                            }
                        }
                        .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsLabeledControl(
                        "settings_sort_option_title".localized,
                        subtitle: "settings_sort_option_sub".localized
                    ) {
                        Picker("", selection: $settings.processSortOption) {
                            ForEach(ProcessSortOption.allCases) { option in
                                Text(option.localizedName).tag(option)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
        )
    }
}
