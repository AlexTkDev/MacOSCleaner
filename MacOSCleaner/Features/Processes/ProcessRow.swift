import SwiftUI

struct ProcessRow: View {
    let process: RunningProcess
    let permission: KillPermission
    let isSelected: Bool
    let onTerminate: () -> Void
    let onForceKill: () -> Void
    let onToggleSelection: () -> Void

    @State private var appIcon: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    if case .blocked = permission {
                        Text("processes_protected".localized)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                            .foregroundColor(.orange)
                    } else if case .needsConfirmation = permission {
                        Text("?")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.yellow.opacity(0.15))
                            )
                            .foregroundColor(.yellow)
                    }
                }

                HStack(spacing: 8) {
                    Text("PID \(process.pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let path = process.path {
                        Text(path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 12) {
                    if process.cpuPercent > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                            Text(process.cpuFormatted)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(process.cpuPercent > 50 ? .red : .secondary)
                    }

                    if process.memoryBytes > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 10))
                            Text(process.memoryFormatted)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(process.memoryBytes > 1_000_000_000 ? .red : .secondary)
                    }

                    if process.threadCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "number")
                                .font(.system(size: 10))
                            Text("\(process.threadCount)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                    }

                    if let uptime = process.uptimeFormatted {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(uptime)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                    }
                }

                if case .blocked(let reason) = permission {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .frame(maxWidth: 200)
                } else {
                    Menu {
                        Button(action: onTerminate) {
                            Label("processes_terminate".localized, systemImage: "xmark.circle")
                        }

                        Button(role: .destructive, action: onForceKill) {
                            Label("processes_force_kill".localized, systemImage: "exclamationmark.triangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                }
            }
        }
        .padding(.vertical, 10)
        .task {
            await loadAppIcon()
        }
    }

    private func loadAppIcon() async {
        guard let path = process.path else { return }
        let icon = await Task.detached {
            NSWorkspace.shared.icon(forFile: path)
        }.value
        appIcon = icon
    }

    private var iconName: String {
        switch permission {
        case .blocked: return "lock.shield"
        case .needsConfirmation: return "questionmark.circle"
        case .allowed: return "checkmark.circle"
        }
    }

    private var iconColor: Color {
        switch permission {
        case .blocked: return .orange
        case .needsConfirmation: return .yellow
        case .allowed: return .accentColor
        }
    }
}
