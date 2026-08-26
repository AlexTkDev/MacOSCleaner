import SwiftUI
import UniformTypeIdentifiers
import AppKit
import OSLog

private extension Logger {
    static let uninstallerView = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "UninstallerView")
}

enum UninstallerTab: String, CaseIterable, Identifiable {
    case applications
    case leftovers

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .applications: return "uninstaller_tab_apps".localized
        case .leftovers: return "uninstaller_tab_leftovers".localized
        }
    }

    var iconName: String {
        switch self {
        case .applications: return "square.grid.2x2"
        case .leftovers: return "shippingbox.and.arrow.backward"
        }
    }
}

struct UninstallerView: View {
    let settings: AppSettings
    let navigateToCleanup: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var service = UninstallerService()
    @State private var selectedTab: UninstallerTab = .applications
    @State private var allApps: [UninstallerService.AppInfo] = []
    @State private var selectedApp: UninstallerService.AppInfo?
    @State private var searchText = ""
    @State private var isTargeted = false
    @State private var showingConfirmation = false
    @State private var isLoading = false
    @State private var isUninstalling = false
    @State private var uninstallingAppName = ""
    @State private var deepScanCache: [String: UninstallerService.AppInfo] = [:]
    @State private var isDeepScanning = false
    @State private var deepScanCompleted = 0
    @State private var deepScanTotal = 0
    @State private var scanTask: Task<Void, Never>? = nil
    @State private var expandedConfidenceTiers: Set<ConfidenceTier> = [.guaranteed, .veryLikely, .possible]
    @State private var versionToUninstall: UninstallerService.AppInfo?
    @State private var showingVersionConfirmation = false
    @State private var selectedVersionID: UUID? = nil
    @State private var postUninstallReport: VerificationReport? = nil
    @State private var showingPostUninstallSheet = false

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
            VStack(spacing: 0) {
                if selectedTab == .applications {
                    applicationsContentView
                } else {
                    OrphanedResidualsView(service: service, settings: settings)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "uninstaller_search".localized)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlassPillPicker(
                    items: UninstallerTab.allCases,
                    selection: $selectedTab,
                    icon: { $0.iconName },
                    label: { $0.localizedTitle }
                )
            }
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
        .sheet(isPresented: $showingPostUninstallSheet) {
            PostUninstallLeftoversSheet(
                report: $postUninstallReport,
                onClean: { selectedItems in
                    cleanPostUninstallLeftovers(selectedItems)
                },
                onDismiss: {
                    showingPostUninstallSheet = false
                    postUninstallReport = nil
                }
            )
        }
        .onAppear {
            if allApps.isEmpty {
                loadApps()
            }
        }
        .onDisappear {
            scanTask?.cancel()
        }
        .onChange(of: selectedApp?.id) { _, newID in
            guard let id = newID else { return }
            guard let app = allApps.first(where: { $0.id == id }) else { return }
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
        .confirmationDialog(
            settings.bypassTrashOnUninstall
                ? "uninstaller_confirm_perm_delete".localized
                : "uninstaller_confirm_move_trash".localized,
            isPresented: $showingVersionConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                settings.bypassTrashOnUninstall
                    ? "uninstaller_delete_permanently".localized
                    : "uninstaller_move_trash".localized,
                role: .destructive
            ) {
                if let versionApp = versionToUninstall, let parentApp = selectedApp {
                    uninstallVersion(versionApp, from: parentApp)
                }
            }
            Button("cancel".localized, role: .cancel) { }
        } message: {
            if let versionApp = versionToUninstall, let parentApp = selectedApp {
                let count = versionApp.relatedFiles.filter(\.isSelected).count + versionApp.developerComponents.filter(\.isSelected).count
                if settings.bypassTrashOnUninstall {
                    Text(String(format: "uninstaller_uninstall_version_warning_perm".localized, versionApp.version, parentApp.name, Int64(count)))
                } else {
                    Text(String(format: "uninstaller_uninstall_version_warning_trash".localized, versionApp.version, parentApp.name, Int64(count)))
                }
            }
        }
    }

    private var applicationsContentView: some View {
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
                                    ProgressView(value: Double(min(deepScanCompleted, deepScanTotal)), total: Double(max(1, deepScanTotal)))
                                        .progressViewStyle(.linear)
                                        .padding(.horizontal, 8)
                                    Text(String(format: "uninstaller.deep_scanning_progress".localized, min(deepScanCompleted, deepScanTotal), deepScanTotal))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor).opacity(reduceTransparency ? 1.0 : 0.15))
                            }
                            List(filteredApps) { app in
                                let unscan = app.scanState != .deepScanned
                                let isThisAppUninstalling = isUninstalling && (selectedApp?.id == app.id)
                                AppRowView(
                                    app: app,
                                    formatter: formatter,
                                    showRelatedFiles: settings.showRelatedFiles,
                                    isUnscannable: unscan,
                                    isUninstalling: isThisAppUninstalling
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isUninstalling else { return }
                                    guard app.scanState == .deepScanned else { return }
                                    selectedVersionID = nil
                                    selectedApp = app
                                }
                                .listRowBackground(
                                    (selectedApp?.id == app.id)
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
                    if isUninstalling {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.4)
                                .controlSize(.large)
                                .padding(.bottom, 4)

                            VStack(spacing: 6) {
                                Text(String(format: "uninstaller_uninstalling_app".localized, uninstallingAppName))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)

                                Text("uninstaller_uninstalling_sub".localized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard(cornerRadius: 16)
                        .padding(24)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else if let app = selectedApp {
                        appDetailView(app)
                            .frame(maxWidth: .infinity)
                    } else {
                        dropZoneView
                            .frame(maxWidth: .infinity)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isUninstalling)
                .layoutPriority(1) // Occupy remaining space
            }
            .padding(.top, 4)
        }
    }

    private func loadApps() {
        scanTask?.cancel()
        isLoading = true
        isDeepScanning = false
        deepScanCompleted = 0
        deepScanTotal = 0
        
        scanTask = Task {
            let fresh = (try? await service.scanAllApplications()) ?? []
            guard !Task.isCancelled else { return }
            
            allApps = fresh
            isLoading = false

            let total = fresh.count
            guard total > 0 else { return }

            isDeepScanning = true
            deepScanCompleted = 0
            deepScanTotal = total

            for app in fresh {
                guard !Task.isCancelled else { break }
                if let result = try? await service.deepScan(app, mode: settings.uninstallerScanMode) {
                    guard !Task.isCancelled else { break }
                    deepScanCompleted = min(deepScanTotal, deepScanCompleted + 1)
                    if let idx = allApps.firstIndex(where: { $0.id == result.id || sameAppURL($0.url, result.url) }) {
                        allApps[idx] = result
                    }
                    if let selected = selectedApp, selected.id == result.id || sameAppURL(selected.url, result.url) {
                        selectedApp = result
                    }
                    deepScanCache[NormalizedPath.key(result.url)] = result
                } else {
                    guard !Task.isCancelled else { break }
                    deepScanCompleted = min(deepScanTotal, deepScanCompleted + 1)
                }
            }

            if !Task.isCancelled {
                isDeepScanning = false
            }
        }
    }

    private func uninstall(_ app: UninstallerService.AppInfo) {
        uninstallingAppName = app.name
        isUninstalling = true
        Task {
            defer {
                isUninstalling = false
            }
            do {
                let report = try await service.uninstall(
                    app: app,
                    bypassTrash: settings.bypassTrashOnUninstall,
                    emptyTrashImmediately: settings.emptyTrashImmediately
                )
                
                await MainActor.run {
                    loadApps()
                    selectedApp = nil
                    if let report = report, report.hasLeftovers {
                        postUninstallReport = report
                        showingPostUninstallSheet = true
                    } else if settings.showNotifications {
                        let title = "uninstaller_complete_title".localized
                        let body = String(format: "uninstaller_complete_body".localized, app.name)
                        NotificationManager.shared.sendNotification(title: title, body: body)
                    }
                }
            } catch {
                Logger.uninstallerView.error("Uninstall failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func uninstallVersion(_ versionApp: UninstallerService.AppInfo, from parentApp: UninstallerService.AppInfo) {
        uninstallingAppName = "\(parentApp.name) v\(versionApp.version)"
        isUninstalling = true
        Task {
            defer {
                isUninstalling = false
            }
            do {
                let report = try await service.uninstall(
                    app: versionApp,
                    bypassTrash: settings.bypassTrashOnUninstall,
                    emptyTrashImmediately: settings.emptyTrashImmediately
                )
                
                await MainActor.run {
                    if let report = report, report.hasLeftovers {
                        postUninstallReport = report
                        showingPostUninstallSheet = true
                    } else if settings.showNotifications {
                        let title = "uninstaller_complete_title".localized
                        let body = String(format: "uninstaller_version_deleted_body".localized, versionApp.version, parentApp.name)
                        NotificationManager.shared.sendNotification(title: title, body: body)
                    }
                    
                    let remaining = parentApp.versions.filter { NormalizedPath.key($0.url) != NormalizedPath.key(versionApp.url) }
                    
                    if remaining.isEmpty {
                        allApps.removeAll { $0.id == parentApp.id }
                        selectedApp = nil
                    } else if remaining.count == 1 {
                        var updatedParent = remaining[0]
                        updatedParent.versions = []
                        if let idx = allApps.firstIndex(where: { $0.id == parentApp.id }) {
                            allApps[idx] = updatedParent
                        }
                        selectedApp = updatedParent
                    } else {
                        var updatedParent = parentApp
                        updatedParent.versions = remaining
                        updatedParent.size = remaining.reduce(0) { $0 + $1.size }
                        if let idx = allApps.firstIndex(where: { $0.id == parentApp.id }) {
                            allApps[idx] = updatedParent
                        }
                        selectedApp = updatedParent
                    }
                }
            } catch {
                Logger.uninstallerView.error("Uninstall version failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func cleanPostUninstallLeftovers(_ items: [LeftoverItem]) {
        guard !items.isEmpty else {
            showingPostUninstallSheet = false
            postUninstallReport = nil
            return
        }

        Task {
            do {
                let freed = try await service.removeLeftovers(items, bypassTrash: settings.bypassTrashOnUninstall)
                await MainActor.run {
                    self.showingPostUninstallSheet = false
                    self.postUninstallReport = nil
                    
                    if settings.showNotifications {
                        let title = "uninstaller_complete_title".localized
                        let body = String(
                            format: "uninstaller_leftovers_cleaned_notification".localized,
                            Int64(items.count),
                            ByteCountFormatter.localizedString(fromByteCount: freed, countStyle: .file)
                        )
                        NotificationManager.shared.sendNotification(title: title, body: body)
                    }
                }
            } catch {
                Logger.uninstallerView.error("Failed to clean leftovers: \(error.localizedDescription, privacy: .public)")
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

                if app.isGrouped {
                    multiVersionSection(app)
                    Divider()
                }

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

    private func multiVersionSection(_ app: UninstallerService.AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundColor(.purple)
                    Text(String(format: "uninstaller_multiple_versions_found".localized, app.versions.count))
                        .font(.headline)
                }
                Spacer()
                if selectedVersionID != nil {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedVersionID = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text(String(format: "uninstaller_all_versions_tab".localized, app.versions.count))
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 8) {
                ForEach(app.versions) { versionApp in
                    let isSelectedVersion = selectedVersionID == versionApp.id

                    HStack(alignment: .center, spacing: 12) {
                        if let iconData = versionApp.iconData ?? app.iconData, let nsImage = NSImage(data: iconData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .cornerRadius(6)
                        } else {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(String(format: "uninstaller_version_title".localized, versionApp.version))
                                    .font(.subheadline)
                                    .fontWeight(.bold)

                                Text(ByteCountFormatter.localizedString(fromByteCount: versionApp.totalSize, countStyle: .file))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)

                                if isSelectedVersion {
                                    Text("✓")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .foregroundColor(.white)
                                        .background(Capsule().fill(Color.accentColor))
                                }
                            }

                            Text(NormalizedPath.displayString(versionApp.url))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button(action: {
                            versionToUninstall = versionApp
                            showingVersionConfirmation = true
                        }) {
                            Label("uninstaller_delete_this_version".localized, systemImage: "trash")
                                .font(.caption)
                        }
                        .destructiveGlassButtonStyle()
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelectedVersion ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelectedVersion ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelectedVersion ? 1.5 : 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedVersionID == versionApp.id {
                                selectedVersionID = nil
                            } else {
                                selectedVersionID = versionApp.id
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func badges(for app: UninstallerService.AppInfo) -> some View {
        if app.isGrouped {
            DetailBadge(title: "uninstaller_versions".localized, value: String(format: "uninstaller_versions_badge".localized, app.versions.count))
        } else {
            DetailBadge(title: "version".localized, value: app.version)
        }
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
                HStack(spacing: 8) {
                    if isUninstalling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isUninstalling ? "uninstaller_uninstalling".localized : "uninstaller_button_uninstall".localized)
                        .font(.headline)
                }
                .frame(maxWidth: 300)
                .frame(height: 32)
            }
            .destructiveGlassButtonStyle()
            .controlSize(.large)
            .disabled(isUninstalling)
        }
    }

    private func displayedRelatedFiles(for app: UninstallerService.AppInfo) -> [UninstallerService.RelatedFile] {
        guard app.isGrouped, let selectedID = selectedVersionID,
              let selectedVersion = app.versions.first(where: { $0.id == selectedID }) else {
            return app.relatedFiles
        }

        let selectedKey = NormalizedPath.key(selectedVersion.url)
        let otherVersions = app.versions.filter { $0.id != selectedID }
        let otherKeys = Set(otherVersions.map { NormalizedPath.key($0.url) })

        return app.relatedFiles.filter { file in
            let fileKey = NormalizedPath.key(file.url)

            // 1. Exclude other versions' main app bundle or files under another version's bundle
            for otherKey in otherKeys {
                if fileKey == otherKey || fileKey.hasPrefix(otherKey + "/") {
                    return false
                }
            }

            // 2. Include files under selected version's bundle URL
            if fileKey == selectedKey || fileKey.hasPrefix(selectedKey + "/") {
                return true
            }

            // 3. Include files scanned specifically for selectedVersion
            return selectedVersion.relatedFiles.contains { NormalizedPath.key($0.url) == fileKey }
        }
    }

    private func displayedDeveloperComponents(for app: UninstallerService.AppInfo) -> [UninstallerService.RelatedCleanupComponent] {
        guard app.isGrouped, let selectedID = selectedVersionID,
              let selectedVersion = app.versions.first(where: { $0.id == selectedID }) else {
            return app.developerComponents
        }

        let selectedKey = NormalizedPath.key(selectedVersion.url)
        let otherVersions = app.versions.filter { $0.id != selectedID }
        let otherKeys = Set(otherVersions.map { NormalizedPath.key($0.url) })

        return app.developerComponents.filter { comp in
            let compKey = NormalizedPath.key(comp.url)
            for otherKey in otherKeys {
                if compKey == otherKey || compKey.hasPrefix(otherKey + "/") {
                    return false
                }
            }
            if compKey == selectedKey || compKey.hasPrefix(selectedKey + "/") {
                return true
            }
            return selectedVersion.developerComponents.contains { NormalizedPath.key($0.url) == compKey }
        }
    }

    private func versionBadgeText(for fileURL: URL, in app: UninstallerService.AppInfo) -> String? {
        guard app.isGrouped, !app.versions.isEmpty else { return nil }
        let fileKey = NormalizedPath.key(fileURL)

        var matchingVersions: [UninstallerService.AppInfo] = []

        for v in app.versions {
            let vKey = NormalizedPath.key(v.url)
            if fileKey == vKey || fileKey.hasPrefix(vKey + "/") {
                matchingVersions.append(v)
                continue
            }

            let isUnderOther = app.versions.contains { other in
                other.id != v.id && (fileKey == NormalizedPath.key(other.url) || fileKey.hasPrefix(NormalizedPath.key(other.url) + "/"))
            }
            if !isUnderOther {
                let inRelated = v.relatedFiles.contains { NormalizedPath.key($0.url) == fileKey }
                let inDev = v.developerComponents.contains { NormalizedPath.key($0.url) == fileKey }
                if inRelated || inDev {
                    matchingVersions.append(v)
                }
            }
        }

        if matchingVersions.isEmpty || matchingVersions.count == app.versions.count {
            return nil
        } else {
            let versionNames = matchingVersions.map { "v" + ($0.version.isEmpty ? "1.0" : $0.version) }
            return versionNames.joined(separator: ", ")
        }
    }

    private func relatedFilesSection(_ app: UninstallerService.AppInfo) -> some View {
        let displayFiles = displayedRelatedFiles(for: app)
        let grouped = Dictionary(grouping: displayFiles) { $0.confidence }
        let allTiers = ConfidenceTier.allCases.filter { $0 != .ignore }.sorted(by: >)
        let visibleTiers = allTiers
        let selectedCount = displayFiles.filter(\.isSelected).count
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleTiers, id: \.self) { tier in
                let files = grouped[tier] ?? []
                if !files.isEmpty {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedConfidenceTiers.contains(tier) },
                            set: { expanded in
                                if expanded {
                                    expandedConfidenceTiers.insert(tier)
                                } else {
                                    expandedConfidenceTiers.remove(tier)
                                }
                            }
                        )
                    ) {
                        VStack(spacing: 1) {
                            ForEach(files) { file in
                                RelatedFileRow(
                                    file: file,
                                    appName: app.name,
                                    settings: settings,
                                    formatter: formatter,
                                    versionBadge: versionBadgeText(for: file.url, in: app),
                                    onToggle: { toggleSelection(file, in: app) }
                                )
                            }
                        }
                        .glassCard(cornerRadius: 10)
                    } label: {
                        Label(tier.displayKey.localized, systemImage: tierIcon(tier))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(tierColor(tier))
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
        let displayComps = displayedDeveloperComponents(for: app)
        return VStack(alignment: .leading, spacing: 6) {
            Label("uninstaller_developer_components".localized, systemImage: "wrench.adjustable")
                .font(.caption)
                .fontWeight(.semibold)

            VStack(spacing: 1) {
                ForEach(Array(displayComps.enumerated()), id: \.element.id) { index, component in
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
                            HStack(spacing: 4) {
                                Text(component.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let badge = versionBadgeText(for: component.url, in: app) {
                                    Text(badge)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .foregroundStyle(Color.purple)
                                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                                }
                            }
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
    var isUninstalling: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if isUninstalling {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
            } else if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if app.isGrouped {
                        Text(String(format: "uninstaller_versions_badge".localized, app.versions.count))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(Color.purple)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                    }
                }
                if isUninstalling {
                    Text("uninstaller_uninstalling".localized)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                } else if isUnscannable {
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
    var versionBadge: String? = nil
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
                          ? SharedBadgeView.sharedComponentHelp(for: file.url)
                          : "")

                Image(systemName: file.deletionRisk == .shared ? "link.circle.fill" : "folder.fill")
                    .foregroundColor(riskColor.opacity(0.8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(file.url.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(1)
                        if let versionBadge = versionBadge {
                            Text(versionBadge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .foregroundStyle(Color.purple)
                                .background(Capsule().fill(Color.purple.opacity(0.12)))
                        }
                        if file.deletionRisk == .shared {
                            SharedBadgeView(url: file.url, riskColor: riskColor)
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

struct SharedBadgeView: View {
    let url: URL
    let riskColor: Color
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "link")
                .font(.system(size: 8, weight: .semibold))
            Text("uninstaller.shared_component".localized)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(riskColor)
        .background(Capsule().fill(riskColor.opacity(isHovered ? 0.25 : 0.12)))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(Self.sharedComponentHelp(for: url))
        .popover(isPresented: $isHovered, arrowEdge: .top) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(riskColor)
                    .font(.body)
                Text(Self.sharedComponentHelp(for: url))
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: 280)
        }
    }

    static func sharedComponentHelp(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("microsoft") || path.contains("office") || path.contains("ubf8t346g9") {
            return "uninstaller.shared_help.microsoft".localized
        } else if path.contains("google") || path.contains("keystone") {
            return "uninstaller.shared_help.google".localized
        } else if path.contains("adobe") {
            return "uninstaller.shared_help.adobe".localized
        } else if path.contains("jetbrains") {
            return "uninstaller.shared_help.jetbrains".localized
        } else if path.contains("android") || path.contains("gradle") {
            return "uninstaller.shared_help.android".localized
        } else if path.contains("developer") || path.contains("coresimulator") {
            return "uninstaller.shared_help.apple_developer".localized
        } else {
            return "uninstaller.shared_component.help".localized
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
