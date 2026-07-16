import SwiftUI
import UserNotifications
import FoundationModels

// MARK: - SettingsView

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let permissionsManager: PermissionsManager
    let onForget: () -> Void
    @Binding var availableUpdate: String?

    @State private var showResetConfirmation = false
    @State private var trashManager = TrashManager()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isCheckingForUpdates = false

    var body: some View {
        Form {
            permissionsSection
            generalSection
            processesSection
            uninstallerSection
            aiSection
            startupSection
            trashDeletionSection
            advancedSection
            resetSection
        }
        .formStyle(.grouped)
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

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("permissions.full_disk_access".localized)
                    Text("settings_fda_description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    if permissionsManager.hasFullDiskAccess {
                        Label("permissions_status_granted".localized, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("permissions_status_required".localized, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }

                    Button {
                        permissionsManager.openFullDiskAccessSettings()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.caption)
                .labelStyle(.iconOnly)
            }

            Button {
                permissionsManager.refresh()
            } label: {
                Label("settings_check_permissions".localized, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        } header: {
            Label("settings_permissions".localized, systemImage: "lock.shield")
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Picker("settings_language".localized, selection: $settings.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .tooltip("settings_tooltip_language".localized, enabled: settings.showTooltips)

            Picker("settings_theme".localized, selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.localizedName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .tooltip("settings_tooltip_theme".localized, enabled: settings.showTooltips)

            Toggle("settings_notifications".localized, isOn: $settings.showNotifications)
                .tooltip("settings_tooltip_notifications".localized, enabled: settings.showTooltips)

            if settings.showNotifications {
                notificationStatusView
            }

            Toggle("settings_tooltips".localized, isOn: $settings.showTooltips)
                .tooltip("settings_tooltip_tooltips".localized, enabled: settings.showTooltips)

            Toggle("settings_auto_scan".localized, isOn: $settings.autoScanOnStartup)
                .tooltip("settings_tooltip_auto_scan".localized, enabled: settings.showTooltips)

            HStack {
                Text("update.check".localized)
                Spacer()
                if isCheckingForUpdates {
                    ProgressView().controlSize(.small)
                    Text("update.checking".localized).foregroundStyle(.secondary)
                } else if let version = availableUpdate {
                    Button {
                        NSWorkspace.shared.open(UpdateChecker.releasesURL)
                    } label: {
                        Text(String(format: "update.available".localized, version))
                    }
                    .buttonStyle(.link)
                } else {
                    Text("update.up_to_date".localized).foregroundStyle(.secondary)
                    Button {
                        Task {
                            isCheckingForUpdates = true
                            availableUpdate = await UpdateChecker().checkForUpdate()
                            isCheckingForUpdates = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Label("settings_general".localized, systemImage: "gearshape")
        }
    }

    // MARK: - Processes

    private var processesSection: some View {
        Section {
            Picker("settings_refresh_interval".localized, selection: $settings.processRefreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.localizedName).tag(interval)
                }
            }
            .tooltip("settings_tooltip_refresh_interval".localized, enabled: settings.showTooltips)

            Picker("settings_sort_by".localized, selection: $settings.processSortOption) {
                ForEach(ProcessSortOption.allCases) { option in
                    Text(option.localizedName).tag(option)
                }
            }
            .tooltip("settings_tooltip_sort_by".localized, enabled: settings.showTooltips)
        } header: {
            Label("settings_processes".localized, systemImage: "cpu")
        }
    }

    // MARK: - Uninstaller

    private var uninstallerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Picker("scan_mode".localized, selection: $settings.uninstallerScanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(ScanMode.allCases) { mode in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: settings.uninstallerScanMode == mode
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.uninstallerScanMode == mode
                                             ? (mode == .safe ? Color.blue : Color.green)
                                             : Color.secondary)
                            .font(.caption)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(mode.localizedName)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                if mode == .balanced {
                                    Text("scan_mode.balanced.default".localized)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
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
                }
            }
        } header: {
            Label("settings_uninstaller".localized, systemImage: "trash.slash")
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section {
            StartupVendorSettingsView()
        } header: {
            Label("settings_startup".localized, systemImage: "bolt.horizontal.circle")
        }
    }

    // MARK: - Trash & Deletion

    private var trashDeletionSection: some View {
        Section {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("settings_trash_warning".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("settings_empty_trash_during_cleanup".localized, isOn: $settings.emptyTrashDuringCleanup)
                .tooltip("settings_tooltip_empty_trash".localized, enabled: settings.showTooltips)
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

            Toggle("settings_bypass_trash_on_uninstall".localized, isOn: $settings.bypassTrashOnUninstall)
                .tooltip("settings_tooltip_bypass_trash".localized, enabled: settings.showTooltips)

            Toggle("settings_empty_trash_immediately".localized, isOn: $settings.emptyTrashImmediately)
                .tooltip("settings_tooltip_empty_trash_immediately".localized, enabled: settings.showTooltips)
        } header: {
            Label("settings_trash_deletion".localized, systemImage: "trash")
        }
    }

    // MARK: - Apple Intelligence

    private var aiSection: some View {
        Section {
            Toggle("settings_enable_ai".localized, isOn: $settings.enableAI)
                .tooltip("settings_tooltip_enable_ai".localized, enabled: settings.showTooltips)

            HStack {
                Text("settings_ai_status".localized)
                    .foregroundStyle(.secondary)
                Spacer()
                aiStatusLabel
            }
        } header: {
            Label("settings_ai_title".localized, systemImage: "sparkles")
        }
    }

    @ViewBuilder
    private var aiStatusLabel: some View {
        if !settings.enableAI {
            Label("settings_ai_status_disabled".localized, systemImage: "slash.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            let status = SystemLanguageModel.default.availability
            switch status {
            case .available:
                Label("settings_ai_status_ready".localized, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    Label("settings_ai_status_unsupported_device".localized, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                case .appleIntelligenceNotEnabled:
                    Label("settings_ai_status_not_enabled".localized, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                case .modelNotReady:
                    Label("settings_ai_status_downloading".localized, systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                @unknown default:
                    Label("settings_ai_status_unavailable".localized, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            Toggle("settings_show_related".localized, isOn: $settings.showRelatedFiles)
                .tooltip("settings_tooltip_show_related".localized, enabled: settings.showTooltips)
        } header: {
            Label("settings_advanced".localized, systemImage: "wrench.and.screwdriver")
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings_forget_everything".localized)
                    Text("settings_forget_description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("settings_reset_button".localized, role: .destructive) {
                    showResetConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .tooltip("settings_tooltip_forget".localized, enabled: settings.showTooltips)
            }
        } header: {
            Label("settings_data".localized, systemImage: "arrow.counterclockwise")
        }
    }

    // MARK: - Notification Status

    private var notificationStatusView: some View {
        HStack {
            Text("settings_notifications_status".localized)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Group {
                    switch notificationStatus {
                    case .authorized:
                        Label("settings_notifications_granted".localized, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .denied:
                        Label("settings_notifications_denied".localized, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    case .notDetermined:
                        Label("settings_notifications_not_determined".localized, systemImage: "questionmark.circle.fill")
                            .foregroundStyle(.orange)
                    case .provisional:
                        Label("permissions.notification_provisional".localized, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    case .ephemeral:
                        Label("permissions.notification_ephemeral".localized, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    @unknown default:
                        Label("permissions.unknown_status".localized, systemImage: "questionmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
                .font(.caption)
                .labelStyle(.iconOnly)

                if notificationStatus == .denied {
                    Button("settings_open_notification_settings".localized) {
                        NotificationManager.shared.openNotificationSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
        .onAppear { updateNotificationStatus() }
        .onChange(of: settings.showNotifications) { _, _ in updateNotificationStatus() }
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

// MARK: - Conditional Tooltip

private extension View {
    @ViewBuilder
    func tooltip(_ text: String, enabled: Bool) -> some View {
        if enabled {
            self.help(text)
        } else {
            self
        }
    }
}

#Preview {
    SettingsView(
        settings: AppSettings(),
        permissionsManager: PermissionsManager(),
        onForget: {},
        availableUpdate: .constant("1.5.0")
    )
    .frame(width: 700, height: 700)
}
