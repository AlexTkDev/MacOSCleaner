import SwiftUI

struct PermissionsView: View {
    @Bindable var permissionsManager: PermissionsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusCard
                    instructionsCard
                    actionButtons
                }
                .padding(24)
            }

            dismissBar
        }
        .frame(minWidth: 450, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("permissions_title".localized)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("permissions_subtitle".localized)
                    .font(.subheadline)
                    .opacity(0.85)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background {
            LinearGradient(
                colors: [
                    .accentColor.opacity(colorScheme == .dark ? 0.8 : 0.65),
                    .accentColor.opacity(colorScheme == .dark ? 0.3 : 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title2)
                .foregroundColor(permissionsManager.hasFullDiskAccess ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("permissions.full_disk_access".localized)
                        .font(.headline)
                    Spacer()
                    statusBadge(isGranted: permissionsManager.hasFullDiskAccess)
                }
                Text("permissions_fda_description".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }

    // MARK: - Instructions Card

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("permissions_instructions_title".localized)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                instructionStep(number: 1, text: "permissions_step1".localized)
                instructionStep(number: 2, text: "permissions_step2".localized)
                instructionStep(number: 3, text: "permissions_step3".localized)
                instructionStep(number: 4, text: "permissions_step4".localized)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                permissionsManager.openFullDiskAccessSettings()
            } label: {
                Label("permissions_open_settings".localized, systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                permissionsManager.refresh()
            } label: {
                Label("permissions_check_status".localized, systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var dismissBar: some View {
        HStack {
            Button("permissions_dismiss_temp".localized) {
                permissionsManager.dismissGuidanceTemporarily()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            Button("permissions_dismiss_permanent".localized) {
                GlassOverlayManager.shared.showAlert(
                    title: "permissions_warning_title".localized,
                    message: "permissions_warning_message".localized,
                    type: .warning,
                    primaryButtonTitle: "permissions_warning_confirm".localized,
                    primaryAction: {
                        permissionsManager.dismissGuidancePermanently()
                    }
                )
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Components

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

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())

            Text(text)
                .font(.callout)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    let manager = PermissionsManager()
    manager.showGuidance = true
    return PermissionsView(permissionsManager: manager)
}
