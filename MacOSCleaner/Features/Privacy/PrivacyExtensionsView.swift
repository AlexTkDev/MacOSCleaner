import AppKit
import SwiftUI

struct PrivacyExtensionsView: View {
    @Bindable var viewModel: PrivacyViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingExtensions && viewModel.extensions.isEmpty {
                AnimatedScanView(
                    title: "privacy_ext_scanning".localized,
                    subtitle: "",
                    currentStep: 0,
                    totalSteps: 1
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        headerInfo
                        browserFilterBar

                        if viewModel.filteredExtensions.isEmpty {
                            ContentUnavailableView(
                                "privacy_ext_empty".localized,
                                systemImage: "puzzlepiece.extension"
                            )
                            .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.filteredExtensions) { ext in
                                extensionCard(ext)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var headerInfo: some View {
        Text("privacy_ext_readonly_note".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 12)
    }

    private var browserFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                browserChip(title: "privacy_filter_all".localized, isSelected: viewModel.browserFilter == nil) {
                    viewModel.browserFilter = nil
                }
                ForEach(ExtensionBrowser.allCases) { browser in
                    let count = viewModel.extensions.filter { $0.browser == browser }.count
                    if count > 0 {
                        browserChip(
                            title: "\(browser.displayName) (\(count))",
                            isSelected: viewModel.browserFilter == browser
                        ) {
                            viewModel.browserFilter = (viewModel.browserFilter == browser) ? nil : browser
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func browserChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12)))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func extensionCard(_ ext: BrowserExtensionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: ext.browser.iconName)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ext.name)
                            .font(.subheadline.weight(.semibold))
                        Text("v\(ext.version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        StatusPill(ext.browser.displayName, style: .neutral, size: .small)
                        StatusPill(
                            ext.source.localizedTitle,
                            style: ext.source == .sideload ? .warning : .info,
                            size: .small
                        )
                        StatusPill(
                            ext.risk.localizedTitle,
                            style: riskStyle(ext.risk),
                            size: .small
                        )
                    }

                    HStack(spacing: 8) {
                        Text(ext.extensionID)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let profile = ext.profileName {
                            Text("• \(profile)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let enabled = ext.isEnabled {
                            Text(enabled ? "privacy_ext_enabled".localized : "privacy_ext_disabled".localized)
                                .font(.caption2)
                                .foregroundStyle(enabled ? .green : .secondary)
                        }
                    }
                }

                Spacer()

                Button("privacy_ext_open_in_browser".localized) {
                    Task { await viewModel.openExtensionInBrowser(ext) }
                }
                .secondaryGlassButtonStyle()
                .controlSize(.small)
            }

            let allPerms = ext.permissions + ext.hostPermissions
            if !allPerms.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Text("privacy_ext_permissions_label".localized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(allPerms.joined(separator: ", "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(ext.highRiskPermissions.isEmpty ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await viewModel.openExtensionInBrowser(ext) }
        }
        .contextMenu {
            Button {
                Task { await viewModel.openExtensionInBrowser(ext) }
            } label: {
                Label("privacy_ext_open_in_browser".localized, systemImage: "safari")
            }
            if let fileURL = ext.bundleOrManifestURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Label("uninstaller_show_in_finder".localized, systemImage: "folder")
                }
            }
        }
    }

    private func riskStyle(_ risk: ExtensionPermissionRisk) -> StatusPillStyle {
        switch risk {
        case .normal: return .success
        case .elevated: return .info
        case .high: return .warning
        }
    }
}
