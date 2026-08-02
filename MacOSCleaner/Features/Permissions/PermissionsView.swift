import SwiftUI

struct PermissionsView: View {
    @Bindable var permissionsManager: PermissionsManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    instructionsCard
                    actionButtons
                }
                .padding(20)

                dismissBar
            }
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
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

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("close".localized)
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

            VStack(alignment: .leading, spacing: 4) {
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
        .padding(14)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Instructions Card

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("permissions_instructions_title".localized)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                instructionStep(number: 1, text: "permissions_step1".localized)
                instructionStep(number: 2, text: "permissions_step2".localized)
                instructionStep(number: 3, text: "permissions_step3".localized)
                instructionStep(number: 4, text: "permissions_step4".localized)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                permissionsManager.openFullDiskAccessSettings()
            } label: {
                Label("permissions_open_settings".localized, systemImage: "gear")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .glassButtonStyle()
            .controlSize(.large)

            Button {
                permissionsManager.refresh()
            } label: {
                Label("permissions_check_status".localized, systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .glassButtonStyle()
            .controlSize(.large)
        }
    }

    private var dismissBar: some View {
        HStack {
            Button("permissions_dismiss_temp".localized) {
                permissionsManager.dismissGuidanceTemporarily()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.caption)
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
                        dismiss()
                    }
                )
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Components

    private func statusBadge(isGranted: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(isGranted ? "permissions_status_granted".localized : "permissions_status_required".localized)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isGranted ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
        .cornerRadius(6)
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.15))
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
