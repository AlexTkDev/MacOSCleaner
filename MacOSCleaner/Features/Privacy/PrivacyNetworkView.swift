import AppKit
import SwiftUI

struct PrivacyNetworkView: View {
    @Bindable var viewModel: PrivacyViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingNetwork && viewModel.networkSnapshot == nil {
                AnimatedScanView(
                    title: "privacy_net_scanning".localized,
                    subtitle: "",
                    currentStep: 0,
                    totalSteps: 1
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = viewModel.networkSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        limitationHeader(snapshot)
                        filterPicker

                        if viewModel.filteredNetworkItems.isEmpty {
                            ContentUnavailableView(
                                "privacy_net_empty".localized,
                                systemImage: "network.slash"
                            )
                            .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.filteredNetworkItems) { item in
                                networkItemCard(item)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func limitationHeader(_ snapshot: NetworkSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusPill(
                    String(format: "privacy_net_uid_badge".localized, Int64(snapshot.currentUID)),
                    iconName: "person.fill",
                    style: .info,
                    size: .small
                )
                StatusPill(
                    String(format: "privacy_net_sockets_count".localized, Int64(snapshot.activeSocketCount)),
                    iconName: "dot.radiowaves.left.and.right",
                    style: .success,
                    size: .small
                )
                if snapshot.restrictedProcessCount > 0 {
                    StatusPill(
                        String(format: "privacy_net_eperm_count".localized, Int64(snapshot.restrictedProcessCount)),
                        iconName: "lock.fill",
                        style: .warning,
                        size: .small
                    )
                }
                Spacer()
                Text(snapshot.capturedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("privacy_net_limitation_note".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    private var filterPicker: some View {
        GlassPillPicker(
            items: NetworkFilterMode.allCases,
            selection: $viewModel.networkFilterMode,
            label: { $0.localizedTitle }
        )
    }

    private func networkItemCard(_ item: AppNetworkItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let url = item.bundleURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: item.isRestrictedByPermissions ? "lock.shield" : "terminal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                        if let pid = item.pid {
                            Text("PID \(pid)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if !item.isRunning {
                            StatusPill("privacy_net_not_running".localized, style: .neutral, size: .small)
                        }
                    }
                    if let bundleID = item.bundleID {
                        Text(bundleID)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if item.isRestrictedByPermissions {
                    StatusPill("privacy_net_eperm_badge".localized, iconName: "lock.fill", style: .warning, size: .small)
                }
            }

            if !item.sockets.isEmpty {
                Divider()
                ForEach(item.sockets) { socket in
                    HStack(spacing: 8) {
                        StatusPill(socket.proto.rawValue, style: socket.proto == .tcp ? .info : .neutral, size: .small)
                        Text(socket.local.displayString)
                            .font(.system(.caption, design: .monospaced))
                        if let remote = socket.remote {
                            Text("→ \(remote.displayString)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let state = socket.state {
                            Text(state)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let profile = item.staticProfile, profile.hasAnyCapability {
                Divider()
                staticProfileSummary(profile)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    private func staticProfileSummary(_ profile: StaticNetworkProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if profile.atsAllowsArbitraryLoads {
                Label("privacy_net_ats_arbitrary".localized, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !profile.atsExceptionDomains.isEmpty {
                Text(String(format: "privacy_net_ats_exceptions".localized, profile.atsExceptionDomains.joined(separator: ", ")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !profile.urlSchemes.isEmpty {
                Text(String(format: "privacy_net_url_schemes".localized, profile.urlSchemes.joined(separator: ", ")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !profile.helperServices.isEmpty {
                Text(String(format: "privacy_net_helpers".localized, profile.helperServices.joined(separator: ", ")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
