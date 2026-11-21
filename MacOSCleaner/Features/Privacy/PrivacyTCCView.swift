import AppKit
import SwiftUI

struct PrivacyTCCView: View {
    @Bindable var viewModel: PrivacyViewModel
    let permissionsManager: PermissionsManager

    @State private var showSessionLog = false

    var body: some View {
        Group {
            if viewModel.isLoadingTCC && viewModel.tccSnapshot == nil {
                AnimatedScanView(
                    title: "privacy_tcc_scanning".localized,
                    subtitle: "",
                    currentStep: 0,
                    totalSteps: 1
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = viewModel.tccSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        statusHeader(snapshot)
                        serviceFilterBar

                        if viewModel.filteredTCCGroups.isEmpty {
                            emptyState(snapshot)
                        } else {
                            ForEach(viewModel.filteredTCCGroups) { group in
                                appGroupCard(group)
                            }
                        }

                        if !viewModel.sessionLog.isEmpty {
                            sessionLogSection
                        }
                    }
                    .padding(16)
                }
            }
        }
        .confirmationDialog(
            "privacy_tcc_reset_confirm_title".localized,
            isPresented: Binding(
                get: { viewModel.pendingReset != nil },
                set: { if !$0 { viewModel.pendingReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = viewModel.pendingReset {
                if target.isAppRunning {
                    Button("privacy_tcc_quit_and_reset".localized, role: .destructive) {
                        Task { await viewModel.confirmReset(quitAppFirst: true) }
                    }
                    Button("privacy_tcc_reset_without_quit".localized, role: .destructive) {
                        Task { await viewModel.confirmReset(quitAppFirst: false) }
                    }
                } else {
                    Button("privacy_tcc_reset_action".localized, role: .destructive) {
                        Task { await viewModel.confirmReset(quitAppFirst: false) }
                    }
                }
                Button("cancel".localized, role: .cancel) {
                    viewModel.pendingReset = nil
                }
            }
        } message: {
            if let target = viewModel.pendingReset {
                if target.isAppRunning {
                    Text(String(format: "privacy_tcc_reset_confirm_running_message".localized, target.serviceTitle, target.appName))
                } else {
                    Text(String(format: "privacy_tcc_reset_confirm_message".localized, target.serviceTitle, target.appName))
                }
            }
        }
    }

    private func statusHeader(_ snapshot: TCCSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                dbStatusPill(title: "privacy_tcc_scope_user".localized, status: snapshot.userDBStatus)
                dbStatusPill(title: "privacy_tcc_scope_system".localized, status: snapshot.systemDBStatus)

                Spacer()

                if case .requiresFullDiskAccess = snapshot.userDBStatus {
                    Button("permissions_open_settings".localized) {
                        permissionsManager.openFullDiskAccessSettings()
                    }
                    .secondaryGlassButtonStyle()
                    .controlSize(.small)
                }

                Button("privacy_open_system_settings".localized) {
                    permissionsManager.openPrivacySettings()
                }
                .secondaryGlassButtonStyle()
                .controlSize(.small)
            }

            Text("privacy_tcc_reset_semantics_note".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    @ViewBuilder
    private func dbStatusPill(title: String, status: TCCDatabaseStatus) -> some View {
        switch status {
        case .available:
            StatusPill("\(title): \("privacy_db_available".localized)", iconName: "checkmark.circle.fill", style: .success, size: .small)
        case .requiresFullDiskAccess:
            StatusPill("\(title): \("privacy_db_no_data_fda".localized)", iconName: "questionmark.circle.fill", style: .warning, size: .small)
        case .sipProtected:
            StatusPill("\(title): \("privacy_db_sip_protected".localized)", iconName: "lock.fill", style: .neutral, size: .small)
        case .unavailable(let reason):
            StatusPill("\(title): \(reason)", iconName: "exclamationmark.triangle.fill", style: .warning, size: .small)
        }
    }

    private var serviceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(title: "privacy_filter_all".localized, isSelected: viewModel.tccServiceFilter == nil) {
                    viewModel.tccServiceFilter = nil
                }
                ForEach(viewModel.availableTCCServices) { service in
                    filterChip(
                        title: service.localizedTitle,
                        icon: service.iconName,
                        isSelected: viewModel.tccServiceFilter == service
                    ) {
                        viewModel.tccServiceFilter = (viewModel.tccServiceFilter == service) ? nil : service
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12)))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func appGroupCard(_ group: TCCAppGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let url = group.appURL {
                    CachedFileIconView(path: url.path, size: 28, cornerRadius: 6) {
                        Image(systemName: "app.dashed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "app.dashed")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.appName)
                            .font(.subheadline.weight(.semibold))
                        if group.isRunning {
                            StatusPill("privacy_app_running".localized, style: .info, size: .small)
                        }
                    }
                    Text(group.client)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if group.hasResettableEntries {
                    Button("privacy_tcc_reset_all".localized) {
                        viewModel.pendingReset = .allForApp(group: group)
                    }
                    .secondaryGlassButtonStyle()
                    .controlSize(.small)
                    .disabled(viewModel.isResettingTCC)
                }
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(group.entries) { entry in
                    permissionRow(entry, in: group)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 12)
    }

    private func permissionRow(_ entry: TCCPermissionEntry, in group: TCCAppGroup) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.service.iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.service.localizedTitle)
                        .font(.subheadline)
                    StatusPill(
                        entry.authStatus.localizedTitle,
                        style: entry.authStatus == .allowed ? .success : (entry.authStatus == .denied ? .error : .neutral),
                        size: .small
                    )
                    if entry.scope == .system {
                        StatusPill("privacy_tcc_scope_system".localized, style: .neutral, size: .small)
                    }
                }

                if let date = entry.lastModified {
                    Text(String(format: "privacy_tcc_last_modified".localized, date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if entry.isResettable {
                Button("privacy_tcc_reset_action".localized) {
                    viewModel.pendingReset = .single(entry: entry, group: group)
                }
                .secondaryGlassButtonStyle()
                .controlSize(.small)
                .disabled(viewModel.isResettingTCC)
            } else {
                HStack(spacing: 6) {
                    if let key = entry.readOnlyReasonKey {
                        Text(key.localized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        permissionsManager.openPrivacySettings(anchor: entry.service.systemSettingsAnchor)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help("privacy_open_system_settings".localized)
                }
            }
        }
    }

    private var sessionLogSection: some View {
        DisclosureGroup(
            isExpanded: $showSessionLog,
            content: {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.sessionLog) { log in
                        HStack(spacing: 8) {
                            Image(systemName: log.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(log.succeeded ? .green : .red)
                                .font(.caption)
                            Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(log.message)
                                .font(.caption)
                        }
                    }
                }
                .padding(.top, 6)
            },
            label: {
                Text(String(format: "privacy_tcc_session_log_title".localized, Int64(viewModel.sessionLog.count)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        )
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    private func emptyState(_ snapshot: TCCSnapshot) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
            if case .requiresFullDiskAccess = snapshot.userDBStatus, snapshot.groups.isEmpty {
                Text("privacy_tcc_empty_no_fda".localized)
                    .font(.headline)
                Text("privacy_tcc_empty_no_fda_sub".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("privacy_tcc_empty".localized)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
