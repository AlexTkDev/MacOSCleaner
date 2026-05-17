import SwiftUI
import UniformTypeIdentifiers

struct UninstallerView: View {
    @State private var service = UninstallerService()
    @State private var allApps: [UninstallerService.AppInfo] = []
    @State private var selectedApp: UninstallerService.AppInfo?
    @State private var isTargeted = false
    @State private var showingConfirmation = false
    @State private var isLoading = false

    var body: some View {
        NavigationSplitView {
            List(allApps, selection: $selectedApp) { app in
                Text(app.url.lastPathComponent.replacingOccurrences(of: ".app", with: ""))
                    .tag(app)
            }
            .navigationTitle("Applications")
            .toolbar {
                Button(action: loadApps) { Image(systemName: "arrow.clockwise") }
            }
        } detail: {
            if let app = selectedApp {
                appDetailsView(app)
            } else {
                dropZoneView
            }
        }
        .onAppear(perform: loadApps)
        .confirmationDialog("Uninstall \(selectedApp?.url.lastPathComponent ?? "app")?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) {
                if let app = selectedApp {
                    Task {
                        try? await service.uninstall(app: app)
                        loadApps()
                        selectedApp = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func loadApps() {
        isLoading = true
        Task {
            allApps = (try? await service.scanAllApplications()) ?? []
            isLoading = false
        }
    }

    private var dropZoneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.circle")
                .font(.system(size: 80))
                .foregroundColor(isTargeted ? Color.accentColor : .secondary)
            Text("Select or Drop Application")
                .font(.title2)
                .bold()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8])).fill(isTargeted ? Color.accentColor : .secondary))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { urlData, _ in
                guard let data = urlData as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self.selectedApp = try? await service.scan(appURL: url)
                }
            }
            return true
        }
    }

    private func appDetailsView(_ app: UninstallerService.AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(app.url.lastPathComponent)
                .font(.title)
                .bold()
            
            Text("Found \(app.relatedFiles.count) related files.")
            
            List(app.relatedFiles, id: \.id) { file in
                HStack {
                    Image(systemName: riskIcon(for: file.url))
                        .foregroundColor(riskColor(for: file.url))
                    Text(file.url.path)
                        .font(.caption)
                        .monospaced()
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Button("Uninstall Application") {
                showingConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private func riskColor(for file: URL) -> Color {
        if file.path.contains("Preferences") { return .orange }
        if file.path.contains("Caches") { return .green }
        return .secondary
    }

    private func riskIcon(for file: URL) -> String {
        if file.path.contains("Preferences") { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }
}
