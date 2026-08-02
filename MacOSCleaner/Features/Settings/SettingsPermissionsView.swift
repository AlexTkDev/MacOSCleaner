import SwiftUI
import UserNotifications

struct SettingsPermissionsView: View {
    let permissionsManager: PermissionsManager
    @Bindable var settings: AppSettings
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showInstructionSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fullDiskAccessCard
                notificationsCard
            }
            .padding(20)
        }
        .onAppear { updateNotificationStatus() }
        .sheet(isPresented: $showInstructionSheet) {
            PermissionsView(permissionsManager: permissionsManager)
        }
    }

    private var fullDiskAccessCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_fda_title".localized, subtitle: "settings_permissions_sub".localized, iconName: "shield.lefthalf.filled", iconColor: permissionsManager.hasFullDiskAccess ? .green : .orange)
            },
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("permissions.full_disk_access".localized)
                                .font(.headline)
                            Text("settings_fda_body".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            permissionsManager.hasFullDiskAccess ? "status_granted".localized : "status_required".localized,
                            style: permissionsManager.hasFullDiskAccess ? .success : .error
                        )
                    }

                    HStack(spacing: 10) {
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
                }
            }
        )
    }

    private var notificationsCard: some View {
        GlassCard(
            header: {
                HStack {
                    Text("settings_notifications".localized)
                        .font(.headline)
                    Spacer()
                    StatusPill(
                        notificationStatus == .authorized ? "status_granted".localized : "status_disabled".localized,
                        style: notificationStatus == .authorized ? .success : .neutral
                    )
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
                        HStack {
                            Text("settings_notifications_denied_body".localized)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("settings_open_settings".localized) {
                                NotificationManager.shared.openNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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
