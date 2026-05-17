import SwiftUI

public struct StartupServicesView: View {
    @State private var viewModel: StartupServicesViewModel
    
    public init(viewModel: StartupServicesViewModel = StartupServicesViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            
            if viewModel.isLoading {
                ProgressView("Scanning services...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.lastError {
                errorView(error)
            } else if viewModel.services.isEmpty {
                emptyView
            } else {
                serviceList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            Task {
                await viewModel.scan()
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Startup Services")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Manage agents that start automatically.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                Task { await viewModel.scan() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help("Refresh list")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private var serviceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.services) { service in
                    ServiceRow(service: service) {
                        Task {
                            await viewModel.toggle(service: service)
                        }
                    }
                    Divider()
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Startup Agents")
                    .font(.headline)
                Text("No agents found in ~/Library/LaunchAgents.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Scan Failed")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button("Try Again") {
                Task { await viewModel.scan() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ServiceRow: View {
    let service: StartupService
    let onToggle: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(service.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(service.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            StatusBadge(isEnabled: service.isEnabled)
            
            Button(service.isEnabled ? "Disable" : "Enable") {
                onToggle()
            }
            .buttonStyle(.bordered)
            .tint(service.isEnabled ? .red : .accentColor)
            .controlSize(.small)
        }
        .padding(.vertical, 12)
    }
}

struct StatusBadge: View {
    let isEnabled: Bool
    
    var body: some View {
        Text(isEnabled ? "Loaded" : "Unloaded")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
            )
            .foregroundColor(isEnabled ? .green : .secondary)
    }
}

#Preview {
    StartupServicesView()
}
