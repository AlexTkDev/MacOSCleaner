import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct UninstallerView: View {
    @State private var service = UninstallerService()
    @State private var allApps: [UninstallerService.AppInfo] = []
    @State private var selectedApp: UninstallerService.AppInfo?
    @State private var searchText = ""
    @State private var isTargeted = false
    @State private var showingConfirmation = false
    @State private var isExpertMode = false
    @State private var isLoading = false
    
    private let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f
    }()

    var filteredApps: [UninstallerService.AppInfo] {
        if searchText.isEmpty {
            return allApps
        } else {
            return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Apps List
                VStack(spacing: 0) {
                    if isLoading && allApps.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredApps, selection: $selectedApp) { app in
                            AppRowView(app: app, formatter: formatter)
                                .tag(app)
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(width: max(250, geometry.size.width * 0.3)) // 30% width but min 250
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Detail Area
                ZStack {
                    if let app = selectedApp {
                        appDetailView(app)
                            .frame(maxWidth: .infinity)
                    } else {
                        dropZoneView
                            .frame(maxWidth: .infinity)
                    }
                }
                .layoutPriority(1) // Occupy remaining space
            }
        }
        .navigationTitle("Uninstaller")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Apps")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: loadApps) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload Applications")
            }
        }
        .onAppear(perform: loadApps)
        .confirmationDialog(
            "Move to Trash?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let app = selectedApp {
                    uninstall(app)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let app = selectedApp {
                Text("This will move \(app.name) and \(app.relatedFiles.filter(\.isSelected).count) related files to the Trash.")
            }
        }
    }

    private func loadApps() {
        isLoading = true
        Task {
            allApps = (try? await service.scanAllApplications()) ?? []
            isLoading = false
        }
    }

    private func uninstall(_ app: UninstallerService.AppInfo) {
        Task {
            do {
                try await service.uninstall(app: app)
                loadApps()
                selectedApp = nil
            } catch {
                print("Uninstall failed: \(error)")
            }
        }
    }

    private var dropZoneView: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.3))
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                    
                    Text("Drag .app here to scan")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: 400, maxHeight: 300)
            .padding(40)
            .scaleEffect(isTargeted ? 1.05 : 1.0)
            .animation(.spring(), value: isTargeted)
            
            Text("OR SELECT FROM THE LIST")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary.opacity(0.6))
                .tracking(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url, url.pathExtension == "app" else { return }
                Task { @MainActor in
                    if let scanned = try? await service.scan(appURL: url) {
                        self.selectedApp = scanned
                    }
                }
            }
            return true
        }
    }

    private func appDetailView(_ app: UninstallerService.AppInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top, spacing: 20) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .overlay(Image(systemName: "app").foregroundColor(.secondary))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 28, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        
                        Text(app.bundleID ?? "Unknown Bundle ID")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        // Adaptive Badges
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                badges(for: app)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                badges(for: app)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                
                Divider()
                
                // Expert Mode Toggle
                Toggle(isOn: $isExpertMode.animation()) {
                    HStack {
                        Text("Expert Mode")
                            .font(.headline)
                        Text("(select related files)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                
                if isExpertMode {
                    relatedFilesSection(app)
                } else {
                    simpleFilesSection(app)
                }
                
                Spacer(minLength: 40)
                
                // Action Area
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom) {
                        actionInfo
                        Spacer()
                        actionButton(for: app)
                    }
                    VStack(alignment: .trailing, spacing: 16) {
                        HStack {
                            actionInfo
                            Spacer()
                        }
                        actionButton(for: app)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func badges(for app: UninstallerService.AppInfo) -> some View {
        DetailBadge(title: "Version", value: app.version)
        DetailBadge(title: "Size", value: formatter.string(fromByteCount: app.size))
        if let lastUsed = app.lastUsed {
            DetailBadge(title: "Last Used", value: lastUsed.formatted(.dateTime.year().month().day()))
        }
    }

    private var actionInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Reversible Action", systemImage: "arrow.uturn.backward.circle")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Files are moved to the Trash and can be restored.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

    private func actionButton(for app: UninstallerService.AppInfo) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("Total Space to Reclaim: \(formatter.string(fromByteCount: app.totalSize))")
                .font(.headline)
            
            Button(action: { showingConfirmation = true }) {
                Text("Uninstall Application")
                    .font(.headline)
                    .frame(maxWidth: 300)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    private func simpleFilesSection(_ app: UninstallerService.AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(app.relatedFiles.count) Related Files Found", systemImage: "doc.on.doc")
                .font(.headline)
            
            Text("In Expert Mode you can selectively remove leftovers like caches and preferences.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func relatedFilesSection(_ app: UninstallerService.AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cleanup Items", systemImage: "list.bullet.indent")
                .font(.headline)
            
            VStack(spacing: 1) {
                ForEach(app.relatedFiles) { file in
                    RelatedFileRow(file: file, formatter: formatter) {
                        toggleSelection(file, in: app)
                    }
                }
            }
            .background(Color(NSColor.alternatingContentBackgroundColors[0]))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func toggleSelection(_ file: UninstallerService.RelatedFile, in app: UninstallerService.AppInfo) {
        if let appIndex = allApps.firstIndex(where: { $0.id == app.id }),
           let fileIndex = allApps[appIndex].relatedFiles.firstIndex(where: { $0.id == file.id }) {
            allApps[appIndex].relatedFiles[fileIndex].isSelected.toggle()
            if selectedApp?.id == app.id {
                selectedApp = allApps[appIndex]
            }
        }
    }
}

struct AppRowView: View {
    let app: UninstallerService.AppInfo
    let formatter: ByteCountFormatter
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(formatter.string(fromByteCount: app.size))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DetailBadge: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct RelatedFileRow: View {
    let file: UninstallerService.RelatedFile
    let formatter: ByteCountFormatter
    let onToggle: () -> Void
    
    var riskColor: Color {
        let path = file.url.path
        if path.contains("Preferences") { return .orange }
        if path.contains("Application Support") { return .blue }
        if path.contains("Caches") || path.contains("Logs") { return .green }
        return .secondary
    }

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(get: { file.isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
            
            Image(systemName: "folder.fill")
                .foregroundColor(riskColor.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(file.url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(formatter.string(fromByteCount: file.size))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}
