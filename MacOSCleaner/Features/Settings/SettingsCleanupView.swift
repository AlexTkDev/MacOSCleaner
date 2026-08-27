import SwiftUI

struct SettingsCleanupView: View {
    @Bindable var settings: AppSettings
    @State private var trashManager = TrashManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                scanSection
                deletionSection
            }
            .padding(20)
        }
    }

    private var scanSection: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_scan_config".localized, subtitle: "settings_scan_config_sub".localized, iconName: "slider.horizontal.3", iconColor: .teal)
            },
            content: {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsLabeledControl(
                        "scan_mode".localized,
                        subtitle: "settings_scan_mode_sub".localized
                    ) {
                        GlassPillPicker(
                            items: ScanMode.allCases,
                            selection: $settings.uninstallerScanMode,
                            label: { $0.localizedName }
                        )
                    }

                    // Detailed mode descriptions
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ScanMode.allCases) { mode in
                            let isSelected = settings.uninstallerScanMode == mode
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? (mode == .safe ? Color.blue : Color.green) : Color.secondary)
                                    .font(.subheadline)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(mode.localizedName)
                                            .font(.callout.weight(.medium))
                                            .foregroundStyle(isSelected ? .primary : .secondary)

                                        if mode == .balanced {
                                            Text("scan_mode.balanced.default".localized)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.15))
                                                .foregroundStyle(.green)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text(mode.localizedDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(10)
                            .background(isSelected ? Color.primary.opacity(0.04) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    settings.uninstallerScanMode = mode
                                }
                            }
                        }
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        "settings_auto_scan".localized,
                        subtitle: "settings_auto_scan_sub".localized,
                        isOn: $settings.autoScanOnStartup
                    )

                    SettingsDivider()

                    SettingsLabeledControl(
                        "settings_project_artifacts_age".localized,
                        subtitle: "settings_project_artifacts_age_sub".localized
                    ) {
                        GlassPillPicker(
                            items: ProjectArtifactsAgeLimit.allCases,
                            selection: Binding(
                                get: { ProjectArtifactsAgeLimit(rawValue: settings.projectArtifactsOlderThanDays) ?? .days60 },
                                set: { settings.projectArtifactsOlderThanDays = $0.rawValue }
                            ),
                            label: { $0.localizedName }
                        )
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        "settings_show_related".localized,
                        subtitle: "settings_show_related_sub".localized,
                        isOn: $settings.showRelatedFiles
                    )
                }
            }
        )
    }

    private var deletionSection: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_deletion_behavior".localized, subtitle: "settings_deletion_behavior_sub".localized, iconName: "trash.circle.fill", iconColor: .orange)
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("settings_trash_safety_note".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        "settings_empty_trash_during_cleanup".localized,
                        subtitle: "settings_empty_trash_cleanup_sub".localized,
                        isOn: $settings.emptyTrashDuringCleanup
                    )
                    .onChange(of: settings.emptyTrashDuringCleanup) { _, newValue in
                        if newValue {
                            Task {
                                do {
                                    try await trashManager.requestTrashAccess()
                                } catch {
                                    settings.emptyTrashDuringCleanup = false
                                }
                            }
                        }
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        "settings_bypass_trash_on_uninstall".localized,
                        subtitle: "settings_bypass_trash_sub".localized,
                        isOn: $settings.bypassTrashOnUninstall
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        "settings_empty_trash_immediately".localized,
                        subtitle: "settings_empty_trash_immediately_sub".localized,
                        isOn: $settings.emptyTrashImmediately
                    )
                }
            }
        )
    }
}
