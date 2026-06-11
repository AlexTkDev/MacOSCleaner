import SwiftUI

struct ProcessRow: View {
    let process: RunningProcess
    let permission: KillPermission
    let onTerminate: () -> Void
    let onForceKill: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 24)

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
        .padding(.vertical, 10)
    }

    private var iconName: String {
        switch permission {
        case .blocked: return "lock.shield"
        case .needsConfirmation: return "questionmark.circle"
        case .allowed: return "app.circle"
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
