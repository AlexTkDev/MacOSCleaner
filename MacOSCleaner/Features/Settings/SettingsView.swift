import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let permissionsManager: PermissionsManager
    let onForget: () -> Void
    @State private var showResetConfirmation = false
    @State private var trashManager = TrashManager()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                    .padding(.bottom, 8)

                sectionCard { permissionsSection }
                sectionCard { generalSection }
                sectionCard { processesSection }
                sectionCard { startupSection }
                sectionCard { trashDeletionSection }
                sectionCard { advancedSection }
                sectionCard { resetSection }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gear")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("settings_title".localized)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("settings_subtitle".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "settings_permissions".localized, icon: "lock.shield")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Disk Access")
                        .font(.body)
                    Text("settings_fda_description".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    statusBadge(isGranted: permissionsManager.hasFullDiskAccess)

                    Button {
                        permissionsManager.openFullDiskAccessSettings()
                    } label: {
                        Label("settings_open_settings".localized, systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Button {
                permissionsManager.refresh()
            } label: {
                Label("settings_check_permissions".localized, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "settings_general".localized, icon: "gearshape")

            settingRow(
                title: "settings_language".localized,
                tooltip: "settings_tooltip_language".localized
            ) {
                Picker("", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            settingRow(
                title: "settings_theme".localized,
                tooltip: "settings_tooltip_theme".localized
            ) {
                Picker("", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.localizedName).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            settingToggle(
                title: "settings_notifications".localized,
                isOn: $settings.showNotifications,
                tooltip: "settings_tooltip_notifications".localized
            )

            if settings.showNotifications {
                notificationStatusView
                    .onAppear {
                        updateNotificationStatus()
                    }
                    .onChange(of: settings.showNotifications) { _, _ in
                        updateNotificationStatus()
                    }
            }

            settingToggle(
                title: "settings_tooltips".localized,
                isOn: $settings.showTooltips,
                tooltip: "settings_tooltip_tooltips".localized
            )

            settingToggle(
                title: "settings_auto_scan".localized,
                isOn: $settings.autoScanOnStartup,
                tooltip: "settings_tooltip_auto_scan".localized
            )
        }
    }

    // MARK: - Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "settings_processes".localized, icon: "cpu")

            settingRow(
                title: "settings_refresh_interval".localized,
                tooltip: "settings_tooltip_refresh_interval".localized
            ) {
                Picker("", selection: $settings.processRefreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.localizedName).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            settingRow(
                title: "settings_sort_by".localized,
                tooltip: "settings_tooltip_sort_by".localized
            ) {
                Picker("", selection: $settings.processSortOption) {
                    ForEach(ProcessSortOption.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "settings_startup".localized, icon: "bolt.horizontal.circle")
            StartupVendorSettingsView()
        }
    }

    // MARK: - Trash & Deletion

    private var trashDeletionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "settings_trash_deletion".localized, icon: "trash")

            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("settings_trash_warning".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            settingToggle(
                title: "settings_empty_trash_during_cleanup".localized,
                isOn: $settings.emptyTrashDuringCleanup,
                tooltip: "settings_tooltip_empty_trash".localized
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

            settingToggle(
                title: "settings_bypass_trash_on_uninstall".localized,
                isOn: $settings.bypassTrashOnUninstall,
                tooltip: "settings_tooltip_bypass_trash".localized
            )

            settingToggle(
                title: "settings_empty_trash_immediately".localized,
                isOn: $settings.emptyTrashImmediately,
                tooltip: "settings_tooltip_empty_trash_immediately".localized
            )
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "settings_advanced".localized, icon: "wrench.and.screwdriver")

            settingToggle(
                title: "settings_show_related".localized,
                isOn: $settings.showRelatedFiles,
                tooltip: "settings_tooltip_show_related".localized
            )

            settingToggle(
                title: "settings_skip_expert".localized,
                isOn: $settings.skipExpertMode,
                tooltip: "settings_tooltip_skip_expert".localized
            )
        }
    }

    // MARK: - Reset / Forget Everything

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "settings_data".localized, icon: "arrow.counterclockwise")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings_forget_everything".localized)
                        .font(.body)
                    Text("settings_forget_description".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Text("settings_reset_button".localized)
                }
                .conditionalHelp(
                    "settings_tooltip_forget".localized,
                    enabled: settings.showTooltips
                )
            }
            .padding(12)
            .background(Color.red.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Notification Status

    private var notificationStatusView: some View {
        HStack {
            Text("settings_notifications_status".localized)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 8) {
                statusBadge

                if notificationStatus == .denied {
                    Button("settings_open_notification_settings".localized) {
                        NotificationManager.shared.openNotificationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Group {
            switch notificationStatus {
            case .authorized:
                Label("settings_notifications_granted".localized, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .denied:
                Label("settings_notifications_denied".localized, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .notDetermined:
                Label("settings_notifications_not_determined".localized, systemImage: "questionmark.circle.fill")
                    .foregroundColor(.orange)
            case .provisional:
                Label("Provisional", systemImage: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
            case .ephemeral:
                Label("Ephemeral", systemImage: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
            @unknown default:
                Label("Unknown", systemImage: "questionmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    private func updateNotificationStatus() {
        Task {
            let status = await NotificationManager.shared.checkAuthorizationStatus()
            await MainActor.run {
                notificationStatus = status
            }
        }
    }

    // MARK: - Components

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.primary)
    }

    private func settingRow<Content: View>(
        title: String,
        tooltip: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.body)
            Spacer()
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .conditionalHelp(tooltip, enabled: settings.showTooltips)
    }

    private func settingToggle(
        title: String,
        isOn: Binding<Bool>,
        tooltip: String
    ) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .conditionalHelp(tooltip, enabled: settings.showTooltips)
    }

    private func statusBadge(isGranted: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(isGranted ? "permissions_status_granted".localized : "permissions_status_required".localized)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isGranted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Conditional Tooltip Modifier

private extension View {
    @ViewBuilder
    func conditionalHelp(_ text: String, enabled: Bool) -> some View {
        if enabled {
            self.help(text)
        } else {
            self
        }
    }
}

#Preview {
    SettingsView(settings: AppSettings(), permissionsManager: PermissionsManager(), onForget: {})
        .frame(width: 700, height: 700)
}
