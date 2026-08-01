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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var service = UninstallerService()
    @State private var allApps: [UninstallerService.AppInfo] = []
    @State private var selectedApp: UninstallerService.AppInfo?
    @State private var searchText = ""
    @State private var isTargeted = false
    @State private var showingConfirmation = false
    @State private var isLoading = false
    @State private var deepScanCache: [String: UninstallerService.AppInfo] = [:]
    @State private var isDeepScanning = false
    @State private var deepScanCompleted = 0
    @State private var deepScanTotal = 0

    private func sameAppURL(_ lhs: URL, _ rhs: URL) -> Bool {
        NormalizedPath.key(lhs) == NormalizedPath.key(rhs)
    }
    
    private var formatter: ByteCountFormatter {
        let f = ByteCountFormatter.makeLocalized(countStyle: .file)
        f.allowedUnits = [.useAll]
        return f
    }

    var filteredApps: [UninstallerService.AppInfo] {
        if searchText.isEmpty {
            return allApps
        } else {
            return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        GlassEffectContainer {
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
                                    .background(Color(NSColor.controlBackgroundColor).opacity(reduceTransparency ? 1.0 : 0.15))
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
                                        (selectedApp.map { sameAppURL($0.url, app.url) } ?? false)
                                            ? Color.accentColor.opacity(0.1)
                                            : Color.clear
                                    )
                                }
                                .listStyle(.inset)
                                .scrollContentBackground(.hidden)
                            }
                        }
                    }
                    .frame(width: max(250, geometry.size.width * 0.3)) // 30% width but min 250
                    .background(Color(NSColor.controlBackgroundColor).opacity(reduceTransparency ? 1.0 : 0.15))
                    
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
                .padding(.top, 4)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "uninstaller_search".localized)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                // Scan mode badge
                HStack(spacing: 4) {
                    Image(systemName: settings.uninstallerScanMode == .safe ? "shield.checkmark" : "scale.3d")
                    Text(settings.uninstallerScanMode.localizedName)
                }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(
                    settings.uninstallerScanMode == .safe ? Color.blue : Color.green
                )
                .background(
                    Capsule().fill(settings.uninstallerScanMode == .safe ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                )
                .overlay(
                    Capsule().strokeBorder(settings.uninstallerScanMode == .safe ? Color.blue.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 6)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: loadApps) {
                    Image(systemName: "arrow.clockwise")
                }
                .glassButtonStyle()
                .help("uninstaller_reload".localized)
            }
        }
        .onAppear(perform: loadApps)
        .onChange(of: selectedApp?.url) { oldURL, newURL in
            guard let url = newURL else { return }
            guard let app = allApps.first(where: { sameAppURL($0.url, url) }) else { return }
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
                if let result = try? await service.deepScan(app, mode: settings.uninstallerScanMode) {
                    deepScanCompleted += 1
                    if let idx = allApps.firstIndex(where: { sameAppURL($0.url, result.url) }) {
                        allApps[idx] = result
                    }
                    if let selected = selectedApp, sameAppURL(selected.url, result.url) {
                        selectedApp = result
                    }
                    deepScanCache[NormalizedPath.key(result.url)] = result
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
            VStack(alignment: .leading, spacing: 16) {
                // Header
                AppDetailHeaderView(
                    app: app,
                    settings: settings,
                    badges: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { badges(for: app) }
                            VStack(alignment: .leading, spacing: 8) { badges(for: app) }
                        }
                    }
                )
                .id(app.id)

                AppMetadataSection(bundleID: app.bundleID)
                
                Divider()

                if settings.showRelatedFiles {
                    relatedFilesSection(app)

                    if !app.developerComponents.isEmpty {
                        developerComponentsSection(app)
                    }
                }
                
                Spacer()
                    .frame(height: 8)
                
                // Action Area
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom) {
                        actionInfo
                        Spacer()
                        actionButton(for: app)
                    }
                    VStack(alignment: .trailing, spacing: 12) {
                        HStack {
                            actionInfo
                            Spacer()
                        }
                        actionButton(for: app)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func badges(for app: UninstallerService.AppInfo) -> some View {
        DetailBadge(title: "version".localized, value: app.version)
        DetailBadge(title: "size".localized, value: ByteCountFormatter.localizedString(fromByteCount: settings.showRelatedFiles ? app.totalSize : app.size, countStyle: .file))
        if let lastUsed = app.lastUsed {
            DetailBadge(title: "last_used".localized, value: lastUsed.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.currentLocale)))
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
            Text(String(format: "uninstaller_space_reclaim".localized, ByteCountFormatter.localizedString(fromByteCount: sizeToReclaim, countStyle: .file)))
                .font(.headline)
            
            Button(action: { showingConfirmation = true }) {
                Text("uninstaller_button_uninstall".localized)
                    .font(.headline)
                    .frame(maxWidth: 300)
                    .frame(height: 32)
            }
            .destructiveGlassButtonStyle()
            .controlSize(.large)
        }
    }

    private func relatedFilesSection(_ app: UninstallerService.AppInfo) -> some View {
        let grouped = Dictionary(grouping: app.relatedFiles) { $0.confidence }
        let allTiers = ConfidenceTier.allCases.filter { $0 != .ignore }.sorted(by: >)
        let visibleTiers = allTiers
        let selectedCount = app.relatedFiles.filter(\.isSelected).count
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleTiers, id: \.self) { tier in
                let files = grouped[tier] ?? []
                if !files.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(tier.displayKey.localized, systemImage: tierIcon(tier))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(tierColor(tier))

                        VStack(spacing: 1) {
                            ForEach(files) { file in
                                    RelatedFileRow(
                                        file: file,
                                        appName: app.name,
                                        settings: settings,
                                        formatter: formatter,
                                        onToggle: { toggleSelection(file, in: app) }
                                    )
                            }
                        }
                        .glassCard(cornerRadius: 10)
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
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
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
        VStack(alignment: .leading, spacing: 6) {
            Label("uninstaller_developer_components".localized, systemImage: "wrench.adjustable")
                .font(.caption)
                .fontWeight(.semibold)

            VStack(spacing: 1) {
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
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(component.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(component.category.localizedTitle)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(ByteCountFormatter.localizedString(fromByteCount: component.sizeBytes, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(.purple))
                }
            }

            HStack {
                Text("uninstaller_developer_components_description".localized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("uninstaller_open_cleanup".localized) {
                    navigateToCleanup()
                }
                .glassButtonStyle()
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.top, app.relatedFiles.isEmpty ? 0 : 4)
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
                    Text(ByteCountFormatter.localizedString(fromByteCount: showRelatedFiles ? app.totalSize : app.size, countStyle: .file))
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
    let appName: String
    let settings: AppSettings
    let formatter: ByteCountFormatter
    let onToggle: () -> Void

    @State private var isExpanded = false
    @State private var aiExplanation = ""
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var riskColor: Color {
        switch file.deletionRisk {
        case .shared: return .orange
        case .safe: return .green
        case .normal:
            let path = file.url.path
            if path.contains("Preferences") { return .orange }
            if path.contains("Application Support") { return .blue }
            if path.contains("Caches") || path.contains("Logs") { return .green }
            return .secondary
        }
    }

        private var displayPath: String {
        NormalizedPath.displayString(file.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle("", isOn: Binding(get: { file.isSelected }, set: { _ in onToggle() }))
                    .toggleStyle(.checkbox)
                    .help(file.deletionRisk == .shared
                          ? "uninstaller.shared_component.help".localized
                          : "")

                Image(systemName: file.deletionRisk == .shared ? "link.circle.fill" : "folder.fill")
                    .foregroundColor(riskColor.opacity(0.8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(file.url.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(1)
                        if file.deletionRisk == .shared {
                            Text("uninstaller.shared_component".localized)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .foregroundStyle(riskColor)
                                .background(Capsule().fill(riskColor.opacity(0.12)))
                        }
                    }
                    Text(displayPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if settings.enableAI && AIExplanationService.shared.isAvailable {
                    Button {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                        }
                        if isExpanded && aiExplanation.isEmpty && !isGenerating {
                            generateAIExplanation()
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundColor(isExpanded ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("uninstaller_explain_with_ai".localized)
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("uninstaller_show_in_finder".localized)

                Text(ByteCountFormatter.localizedString(fromByteCount: file.size, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().padding(.vertical, 4)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                            .font(.caption)
                        
                        if isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("uninstaller_ai_explaining".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text(aiExplanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func generateAIExplanation() {
        isGenerating = true
        errorMessage = nil
        
        let lang = settings.language
        Task {
            do {
                let evidenceStrings = file.evidence.map { evidence -> String in
                    let explanation = EvidenceExplanations.explanation(for: evidence, args: appName)
                    return "\(explanation.title): \(explanation.description)"
                }
                
                let result = try await AIExplanationService.shared.explainRelation(
                    appName: appName,
                    filePath: file.url.path,
                    evidence: evidenceStrings,
                    deletionRisk: file.deletionRisk.rawValue,
                    language: lang
                )
                
                await MainActor.run {
                    self.aiExplanation = result
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }
}

struct AppDetailHeaderView<BadgeContent: View>: View {
    let app: UninstallerService.AppInfo
    let settings: AppSettings
    @ViewBuilder let badges: BadgeContent
    
    @State private var isExpanded = false
    @State private var aiExplanation = ""
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay(Image(systemName: "app").foregroundColor(.secondary))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 20, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if settings.enableAI && AIExplanationService.shared.isAvailable {
                            Button {
                                withAnimation(.spring()) {
                                    isExpanded.toggle()
                                }
                                if isExpanded && aiExplanation.isEmpty && !isGenerating {
                                    generateAIExplanation()
                                }
                            } label: {
                                Image(systemName: "sparkles")
                                    .foregroundColor(isExpanded ? .purple : .secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .help("uninstaller_explain_with_ai".localized)
                        }
                    }
                    
                    Text(app.bundleID ?? "uninstaller_unknown_bundle".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer(minLength: 12)
                
                badges
                    .layoutPriority(1)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                            .font(.subheadline)
                            .padding(.top, 2)
                        
                        if isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("uninstaller_ai_explaining".localized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = errorMessage {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                        } else {
                            Text(aiExplanation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.all, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                .padding(.top, 8)
            }
        }
    }
    
    private func generateAIExplanation() {
        isGenerating = true
        errorMessage = nil
        
        let lang = settings.language
        let sizeString = ByteCountFormatter.localizedString(fromByteCount: app.size, countStyle: .file)
        
        Task {
            do {
                let result = try await AIExplanationService.shared.explainApp(
                    appName: app.name,
                    bundleID: app.bundleID ?? "Unknown",
                    sizeFormatted: sizeString,
                    language: lang
                )
                
                await MainActor.run {
                    self.aiExplanation = result
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }
}

// MARK: - Registry metadata (lazy-loaded, off critical render path)

private struct AppMetadataSection: View {
    let bundleID: String?
    @State private var metadata: UIMetadata?

    var body: some View {
        Group {
            if let metadata {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        DifficultyBadge(difficulty: metadata.difficulty)
                        if let suite = metadata.parentSuite {
                            DetailBadge(
                                title: "uninstaller.metadata.parent_suite".localized,
                                value: suite
                            )
                        }
                    }

                    if !metadata.knownIssues.isEmpty {
                        Label("uninstaller.metadata.known_issues".localized, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(metadata.knownIssues.enumerated()), id: \.offset) { _, issue in
                                Text(issue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 10)
            }
        }
        .task(id: bundleID) {
            metadata = nil
            guard let bundleID, !bundleID.isEmpty else { return }
            // Fresh provider avoids stale empty cache if Bundle.main resources were not ready yet.
            metadata = await UIMetadataProvider().metadata(forBundleID: bundleID)
        }
    }
}

private struct DifficultyBadge: View {
    let difficulty: UninstallDifficulty

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(difficulty.localizationKey.localized)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foregroundColor)
        .background(
            Capsule().fill(foregroundColor.opacity(0.12))
        )
        .overlay(
            Capsule().strokeBorder(foregroundColor.opacity(0.25), lineWidth: 1)
        )
        .help("uninstaller.metadata.difficulty".localized)
    }

    private var iconName: String {
        switch difficulty {
        case .critical: return "exclamationmark.octagon.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }

    private var foregroundColor: Color {
        switch difficulty {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .secondary
        }
    }
}
