import SwiftUI
import UserNotifications

struct SettingsGeneralView: View {
    @Bindable var settings: AppSettings
    let permissionsManager: PermissionsManager
    @Binding var availableUpdate: String?
    let onForget: () -> Void

    @State private var isCheckingForUpdates = false
    @State private var hasCheckedForUpdates = false
    @State private var showResetConfirmation = false
    @State private var showInstructionSheet = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fullDiskAccessCard
                appearanceCard
                notificationsCard
                updatesCard
                resetCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { updateNotificationStatus() }
        .sheet(isPresented: $showInstructionSheet) {
            PermissionsView(permissionsManager: permissionsManager)
        }
        .confirmationDialog(
            "settings_reset_confirm_title".localized,
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings_reset_confirm_button".localized, role: .destructive) {
                settings.resetAll()
                onForget()
            }
            Button("cancel".localized, role: .cancel) { }
        } message: {
            Text("settings_reset_confirm_message".localized)
        }
    }

    private var appearanceCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_appearance_language".localized, subtitle: "settings_appearance_language_sub".localized, iconName: "gearshape.fill", iconColor: .gray)
            },
            content: {
                VStack(spacing: 12) {
                    SettingsLabeledControl(
                        "settings_language".localized,
                        subtitle: "settings_language_sub".localized
                    ) {
                        Picker("", selection: $settings.language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsLabeledControl(
                        "settings_theme".localized,
                        subtitle: "settings_theme_sub".localized
                    ) {
                        GlassPillPicker(
                            items: AppTheme.allCases,
                            selection: $settings.theme,
                            label: { $0.localizedName }
                        )
                    }

                    SettingsDivider()

                    SettingsToggleRow(
                        "settings_tooltips".localized,
                        subtitle: "settings_tooltips_sub".localized,
                        iconName: "info.circle",
                        isOn: $settings.showTooltips
                    )
                }
            }
        )
    }

    private var updatesCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_software_updates".localized, subtitle: "settings_software_updates_sub".localized, iconName: "arrow.clockwise.circle.fill", iconColor: .blue)
            },
            content: {
                SettingsLabeledControl(
                    "settings_current_version".localized,
                    subtitle: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0")"
                ) {
                    if isCheckingForUpdates {
                        ProgressView().controlSize(.small)
                    } else if let version = availableUpdate {
                        Button(String(format: "update.available".localized, version)) {
                            NSWorkspace.shared.open(UpdateChecker.releasesURL)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.small)
                    } else {
                        Button(hasCheckedForUpdates ? "update.up_to_date".localized : "update.check".localized) {
                            Task {
                                isCheckingForUpdates = true
                                availableUpdate = await UpdateChecker().checkForUpdate()
                                hasCheckedForUpdates = true
                                isCheckingForUpdates = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(hasCheckedForUpdates ? .green : .accentColor)
                        .controlSize(.small)
                    }
                }
            }
        )
    }

    private var resetCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_data".localized, subtitle: "settings_forget_description".localized, iconName: "arrow.counterclockwise.circle.fill", iconColor: .red)
            },
            content: {
                SettingsActionRow(
                    "settings_forget_everything".localized,
                    subtitle: "settings_forget_description".localized,
                    iconName: "trash",
                    buttonTitle: "settings_reset_button".localized,
                    buttonIcon: "trash.fill",
                    isDestructive: true
                ) {
                    showResetConfirmation = true
                }
            },
            isDestructive: true
        )
    }

    private var fullDiskAccessCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_fda_title".localized, subtitle: "settings_permissions_sub".localized, iconName: "shield.lefthalf.filled", iconColor: permissionsManager.hasFullDiskAccess ? .green : .orange)
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsLabeledControl(
                        "permissions.full_disk_access".localized,
                        subtitle: "settings_fda_body".localized
                    ) {
                        StatusPill(
                            permissionsManager.hasFullDiskAccess ? "status_granted".localized : "status_required".localized,
                            style: permissionsManager.hasFullDiskAccess ? .success : .error
                        )
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            fdaButtons
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            fdaButtons
                        }
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var fdaButtons: some View {
        Button("settings_open_privacy_settings".localized) {
            permissionsManager.openFullDiskAccessSettings()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)

        Button("settings_check_status".localized) {
            permissionsManager.refresh()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Button("settings_permission_guide".localized) {
            showInstructionSheet = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var notificationsCard: some View {
        GlassCard(
            header: {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("settings_notifications".localized)
                            .font(.headline)
                        Spacer(minLength: 8)
                        StatusPill(
                            notificationStatus == .authorized ? "status_granted".localized : "status_disabled".localized,
                            style: notificationStatus == .authorized ? .success : .neutral
                        )
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings_notifications".localized)
                            .font(.headline)
                        StatusPill(
                            notificationStatus == .authorized ? "status_granted".localized : "status_disabled".localized,
                            style: notificationStatus == .authorized ? .success : .neutral
                        )
                    }
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        "settings_notifications_enable".localized,
                        subtitle: "settings_notifications_enable_sub".localized,
                        isOn: $settings.showNotifications
                    )

                    if notificationStatus == .denied {
                        SettingsDivider()
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .center, spacing: 12) {
                                Text("settings_notifications_denied_body".localized)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                Button("settings_open_settings".localized) {
                                    NotificationManager.shared.openNotificationSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .fixedSize()
                                .layoutPriority(1)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("settings_notifications_denied_body".localized)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Button("settings_open_settings".localized) {
                                    NotificationManager.shared.openNotificationSettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        )
    }

    private func updateNotificationStatus() {
        Task {
            let status = await NotificationManager.shared.checkAuthorizationStatus()
            await MainActor.run {
                notificationStatus = status
            }
        }
    }
}
