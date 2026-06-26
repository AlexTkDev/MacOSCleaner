import SwiftUI
import UniformTypeIdentifiers
import AppKit
import OSLog

private extension Logger {
    static let uninstallerView = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "UninstallerView")
}

struct UninstallerView: View {
    let settings: AppSettings
    let navigateToCleanup: () -> Void
    @State private var service = UninstallerService()
    @State private var allApps: [UninstallerService.AppInfo] = []
    @State private var selectedApp: UninstallerService.AppInfo?
    @State private var searchText = ""
    @State private var isTargeted = false
    @State private var showingConfirmation = false
    @State private var isLoading = false
    @State private var deepScanCache: [URL: UninstallerService.AppInfo] = [:]
    @State private var isDeepScanning = false
    @State private var deepScanCompleted = 0
    @State private var deepScanTotal = 0
    
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
                    if isLoading {
                        AnimatedScanView(
                            title: "uninstaller_scanning_apps".localized,
                            subtitle: service.progress.message,
                            currentStep: service.progress.currentStep,
                            totalSteps: service.progress.totalSteps
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 0) {
                            if isDeepScanning {
                                VStack(spacing: 4) {
                                    ProgressView(value: Double(deepScanCompleted), total: Double(deepScanTotal))
                                        .progressViewStyle(.linear)
                                        .padding(.horizontal, 8)
                                    Text(String(format: "uninstaller.deep_scanning_progress".localized, deepScanCompleted, deepScanTotal))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor))
                            }
                            List(filteredApps) { app in
                                let unscan = app.scanState != .deepScanned
                                AppRowView(
                                    app: app,
                                    formatter: formatter,
                                    showRelatedFiles: settings.showRelatedFiles,
                                    isUnscannable: unscan
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard app.scanState == .deepScanned else { return }
                                    selectedApp = app
                                }
                                .listRowBackground(
                                    selectedApp?.url == app.url
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear
                                )
                            }
                            .listStyle(.inset)
                        }
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
        .navigationTitle("uninstaller_title".localized)
        .searchable(text: $searchText, placement: .toolbar, prompt: "uninstaller_search".localized)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: loadApps) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("uninstaller_reload".localized)
            }
        }
        .onAppear(perform: loadApps)
        .onChange(of: selectedApp?.url) { oldURL, newURL in
            guard let url = newURL else { return }
            guard let app = allApps.first(where: { $0.url == url }) else { return }
            if app.scanState != .deepScanned {
                selectedApp = nil
            }
        }
        .confirmationDialog(
            settings.bypassTrashOnUninstall
                ? "uninstaller_confirm_perm_delete".localized
                : "uninstaller_confirm_move_trash".localized,
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                settings.bypassTrashOnUninstall
                    ? "uninstaller_delete_permanently".localized
                    : "uninstaller_move_trash".localized,
                role: .destructive
            ) {
                if let app = selectedApp {
                    uninstall(app)
                }
            }
            Button("cancel".localized, role: .cancel) { }
        } message: {
            if let app = selectedApp {
                let count = app.relatedFiles.filter(\.isSelected).count + app.developerComponents.filter(\.isSelected).count
                if settings.bypassTrashOnUninstall {
                    Text(String(format: "uninstaller_uninstall_app_warning_perm".localized, app.name, Int64(count)))
                } else {
                    Text(String(format: "uninstaller_uninstall_app_warning_trash".localized, app.name, Int64(count)))
                }
            }
        }
    }

    private func loadApps() {
        isLoading = true
        Task {
            let fresh = (try? await service.scanAllApplications()) ?? []
            allApps = fresh
            isLoading = false

            let total = fresh.count
            guard total > 0 else { return }

            isDeepScanning = true
            deepScanCompleted = 0
            deepScanTotal = total

            for app in fresh {
                if let result = try? await service.deepScan(app) {
                    deepScanCompleted += 1
                    if let idx = allApps.firstIndex(where: { $0.url == result.url }) {
                        allApps[idx] = result
                    }
                    if selectedApp?.url == result.url {
                        selectedApp = result
                    }
                    deepScanCache[result.url] = result
                } else {
                    deepScanCompleted += 1
                }
            }

            isDeepScanning = false
        }
    }

    private func uninstall(_ app: UninstallerService.AppInfo) {
        Task {
            do {
                try await service.uninstall(
                    app: app,
                    bypassTrash: settings.bypassTrashOnUninstall,
                    emptyTrashImmediately: settings.emptyTrashImmediately
                )
                
                if settings.showNotifications {
                    let title = "uninstaller_complete_title".localized
                    let body = String(format: "uninstaller_complete_body".localized, app.name)
                    NotificationManager.shared.sendNotification(title: title, body: body)
                }
                
                loadApps()
                selectedApp = nil
            } catch {
                Logger.uninstallerView.error("Uninstall failed: \(error.localizedDescription, privacy: .public)")
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
                    
                    Text("uninstaller_drag_drop".localized)
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
            
            Text("uninstaller_or_select".localized)
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
                    if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                        Image(nsImage: nsImage)
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
                        
                        Text(app.bundleID ?? "uninstaller_unknown_bundle".localized)
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

                if settings.showRelatedFiles {
                    relatedFilesSection(app)

                    if !app.developerComponents.isEmpty {
                        developerComponentsSection(app)
                    }
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
        DetailBadge(title: "version".localized, value: app.version)
        DetailBadge(title: "size".localized, value: formatter.string(fromByteCount: settings.showRelatedFiles ? app.totalSize : app.size))
        if let lastUsed = app.lastUsed {
            DetailBadge(title: "last_used".localized, value: lastUsed.formatted(.dateTime.year().month().day()))
        }
    }

    private var actionInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            if settings.bypassTrashOnUninstall {
                Label("uninstaller_action_info_perm".localized, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("uninstaller_action_info_perm_sub".localized)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            } else {
                Label("uninstaller_action_info_trash".localized, systemImage: "arrow.uturn.backward.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("uninstaller_action_info_trash_sub".localized)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }

    private func actionButton(for app: UninstallerService.AppInfo) -> some View {
        let sizeToReclaim = settings.showRelatedFiles ? app.totalSize : app.size
        return VStack(alignment: .trailing, spacing: 8) {
            Text(String(format: "uninstaller_space_reclaim".localized, formatter.string(fromByteCount: sizeToReclaim)))
                .font(.headline)
            
            Button(action: { showingConfirmation = true }) {
                Text("uninstaller_button_uninstall".localized)
                    .font(.headline)
                    .frame(maxWidth: 300)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    private func relatedFilesSection(_ app: UninstallerService.AppInfo) -> some View {
        let grouped = Dictionary(grouping: app.relatedFiles) { $0.confidence }
        let allTiers = ConfidenceTier.allCases.filter { $0 != .ignore }.sorted(by: >)
        let visibleTiers = allTiers
        let selectedCount = app.relatedFiles.filter(\.isSelected).count
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleTiers, id: \.self) { tier in
                let files = grouped[tier] ?? []
                if !files.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(tier.displayKey.localized, systemImage: tierIcon(tier))
                            .font(.subheadline)
                            .foregroundColor(tierColor(tier))

                        VStack(spacing: 1) {
                            ForEach(files) { file in
                                    RelatedFileRow(
                                        file: file,
                                        formatter: formatter,
                                        onToggle: { toggleSelection(file, in: app) }
                                    )
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
            }
            if selectedCount > 0 {
                let tierLabels = allTiers.compactMap { t -> String? in
                    let count = grouped[t]?.count ?? 0
                    guard count > 0 else { return nil }
                    return "\(count) \(t.displayKey.localized)"
                }.joined(separator: ", ")
                Text(String(format: "uninstaller.footer.summary".localized, Int64(selectedCount), tierLabels))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private func tierIcon(_ tier: ConfidenceTier) -> String {
        switch tier {
        case .guaranteed: return "checkmark.shield.fill"
        case .veryLikely: return "shield.fill"
        case .possible: return "questionmark.circle.fill"
        case .ignore: return "slash.circle"
        }
    }

    private func tierColor(_ tier: ConfidenceTier) -> Color {
        switch tier {
        case .guaranteed: return .green
        case .veryLikely: return .blue
        case .possible: return .orange
        case .ignore: return .gray
        }
    }

    private func developerComponentsSection(_ app: UninstallerService.AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("uninstaller_developer_components".localized, systemImage: "wrench.adjustable")
                .font(.headline)

            ForEach(Array(app.developerComponents.enumerated()), id: \.element.id) { index, component in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { component.isSelected },
                        set: { newValue in
                            toggleDeveloperComponent(in: app, at: index, value: newValue)
                        }
                    ))
                    .toggleStyle(.checkbox)

                    Image(systemName: "shippingbox")
                        .foregroundColor(.purple)
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(component.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(component.category.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(formatter.string(fromByteCount: component.sizeBytes))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.purple.opacity(0.04))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
            }

            HStack {
                Text("uninstaller_developer_components_description".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("uninstaller_open_cleanup".localized) {
                    navigateToCleanup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.top, app.relatedFiles.isEmpty ? 0 : 12)
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

    private func toggleDeveloperComponent(in app: UninstallerService.AppInfo, at index: Int, value: Bool) {
        if let appIndex = allApps.firstIndex(where: { $0.id == app.id }) {
            allApps[appIndex].developerComponents[index].isSelected = value
            if selectedApp?.id == app.id {
                selectedApp = allApps[appIndex]
            }
        }
    }
}

struct AppRowView: View {
    let app: UninstallerService.AppInfo
    let formatter: ByteCountFormatter
    let showRelatedFiles: Bool
    let isUnscannable: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
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
                if isUnscannable {
                    Text("uninstaller.analyzing".localized)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                } else {
                    Text(formatter.string(fromByteCount: showRelatedFiles ? app.totalSize : app.size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isUnscannable ? 0.5 : 1.0)
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
                HStack(spacing: 4) {
                    Text(file.url.lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Text(file.url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            Text(formatter.string(fromByteCount: file.size))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}
