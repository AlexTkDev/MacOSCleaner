import SwiftUI

struct SettingsAdvancedView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                developerCard
                startupVendorsCard
            }
            .padding(20)
        }
    }

    private var developerCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_advanced_dev_title".localized, subtitle: "settings_advanced_dev_sub".localized, iconName: "wrench.and.screwdriver.fill", iconColor: .indigo)
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        "settings_show_related_app_files".localized,
                        subtitle: "settings_show_related_app_files_sub".localized,
                        isOn: $settings.showRelatedFiles
                    )
                }
            }
        )
    }

    private var startupVendorsCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("startup_vendors_title".localized, subtitle: "settings_startup_vendors_sub".localized, iconName: "bolt.horizontal.circle.fill", iconColor: .teal)
            },
            content: {
                StartupVendorSettingsView()
            }
        )
    }
}
