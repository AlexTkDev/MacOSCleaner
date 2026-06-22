import SwiftUI

struct PermissionsView: View {
    @Bindable var permissionsManager: PermissionsManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("permissions_title".localized)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("permissions_subtitle".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 20)
            
            Divider()
            
            // FDA Status
            permissionStatusRow(
                icon: "externaldrive.badge.checkmark",
                title: "Full Disk Access",
                description: "permissions_fda_description".localized,
                isGranted: permissionsManager.hasFullDiskAccess
            )
            
            Divider()
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("permissions_instructions_title".localized)
                    .font(.headline)
                
                instructionStep(number: 1, text: "permissions_step1".localized)
                instructionStep(number: 2, text: "permissions_step2".localized)
                instructionStep(number: 3, text: "permissions_step3".localized)
                instructionStep(number: 4, text: "permissions_step4".localized)
            }
            .padding(.horizontal, 8)
            
            Divider()
            
            // Buttons
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
            .padding(.horizontal, 8)
            
            Spacer()
            
            // Dismiss
            HStack {
                Button("permissions_dismiss_temp".localized) {
                    permissionsManager.dismissGuidanceTemporarily()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("permissions_dismiss_permanent".localized) {
                    permissionsManager.dismissGuidancePermanently()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
            }
            .padding(.bottom, 12)
        }
        .padding(24)
        .frame(minWidth: 450, minHeight: 500)
    }
    
    // MARK: - Components
    
    private func permissionStatusRow(icon: String, title: String, description: String, isGranted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    Spacer()
                    
                    statusBadge(isGranted: isGranted)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
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
