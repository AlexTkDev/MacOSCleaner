import SwiftUI

struct StartupVendorSettingsView: View {
    @State private var prefixes: [String] = []
    @State private var newPrefix: String = ""
    @State private var showAddError = false
    @State private var addErrorMessage = ""

    private let manager = LaunchServiceManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            description
            vendorList
            addSection
        }
        .task {
            await loadPrefixes()
        }
    }

    private func loadPrefixes() async {
        prefixes = await manager.systemVendorPrefixes
    }

    private var header: some View {
        Label("startup_vendors_title".localized, systemImage: "list.bullet.rectangle")
            .font(.headline)
            .foregroundColor(.primary)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("startup_vendors_description".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("startup_vendors_description_sub".localized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var vendorList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("startup_vendors_current".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button(action: {
                    Task { await resetToDefaults() }
                }) {
                    Text("startup_vendors_reset".localized)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            if prefixes.isEmpty {
                Text("startup_vendors_empty".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(prefixes.enumerated()), id: \.offset) { index, prefix in
                    HStack {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text(prefix)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if prefix == "com.apple." {
                            Text("startup_vendors_protected".localized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                Task { await removePrefix(prefix) }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    if index < prefixes.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var addSection: some View {
        HStack(spacing: 8) {
            TextField("startup_vendors_placeholder".localized, text: $newPrefix)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    Task { await addPrefix() }
                }

            Button(action: {
                Task { await addPrefix() }
            }) {
                Label("add".localized, systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(newPrefix.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addPrefix() async {
        let trimmed = newPrefix.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        guard trimmed.contains(".") else {
            addErrorMessage = "startup_vendors_error_no_dot".localized
            showAddError = true
            return
        }

        let current = await manager.systemVendorPrefixes
        guard !current.contains(trimmed) else {
            addErrorMessage = "startup_vendors_error_duplicate".localized
            showAddError = true
            return
        }

        await manager.addVendorPrefix(trimmed)
        newPrefix = ""
        await loadPrefixes()
    }

    private func removePrefix(_ prefix: String) async {
        await manager.removeVendorPrefix(prefix)
        await loadPrefixes()
    }

    private func resetToDefaults() async {
        await manager.setSystemVendorPrefixes(["com.apple."])
        await loadPrefixes()
    }
}

#Preview {
    StartupVendorSettingsView()
        .padding()
}
