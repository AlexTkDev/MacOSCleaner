import SwiftUI
import AppKit

struct UpdateAvailableView: View {
    let update: AvailableUpdate
    let currentVersion: String
    let onDismissLater: () -> Void
    let onDismissForVersion: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    versionCard
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
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("update_sheet_title".localized)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("update_sheet_subtitle".localized)
                    .font(.subheadline)
                    .opacity(0.85)
            }

            Spacer()

            Button {
                onDismissLater()
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

    // MARK: - Version Card

    private var versionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "update.available".localized, update.version))
                    .font(.headline)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("update_sheet_current".localized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("v\(currentVersion)")
                            .font(.subheadline.monospacedDigit())
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("update_sheet_latest".localized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("v\(update.version)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let dmgURL = update.dmgURL {
                Button {
                    NSWorkspace.shared.open(dmgURL)
                } label: {
                    Label("update.download_dmg".localized, systemImage: "arrow.down.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .glassButtonStyle()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }

            Button {
                UpdatePromptController.openReleases()
            } label: {
                Label("update.view_releases".localized, systemImage: "link")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .glassButtonStyle()
            .controlSize(.large)
            .keyboardShortcut(update.dmgURL == nil ? .defaultAction : .cancelAction)
        }
    }

    private var dismissBar: some View {
        HStack {
            Button("update.dismiss_later".localized) {
                onDismissLater()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()

            Button("update.dismiss_version".localized) {
                onDismissForVersion()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    UpdateAvailableView(
        update: AvailableUpdate(
            version: "2.2.0",
            dmgURL: URL(string: "https://github.com/AlexTkDev/MacOSCleaner/releases/download/2.2.0/MacOSCleaner.dmg")
        ),
        currentVersion: "2.1.1",
        onDismissLater: {},
        onDismissForVersion: {}
    )
}
