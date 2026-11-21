import SwiftUI

public struct StartupServicesView: View {
    let settings: AppSettings
    @Bindable var viewModel: StartupServicesViewModel
    @State private var serviceToDelete: StartupService? = nil

    public init(settings: AppSettings, viewModel: StartupServicesViewModel = StartupServicesViewModel()) {
        self.settings = settings
        self.viewModel = viewModel
    }

    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                WorkspaceHeaderBar {
                    Spacer()
                    filterPicker
                    Spacer()
                    ScanStatusPill(lastUpdatedAt: viewModel.lastUpdatedAt)
                    Button(action: { Task { await viewModel.scan() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .glassButtonStyle()
                    .help("startup_refresh".localized)
                }

                Divider()

                if viewModel.isLoading && viewModel.services.isEmpty {
                    AnimatedScanView(
                        title: "startup_scanning".localized,
                        subtitle: "",
                        currentStep: 0,
                        totalSteps: 1
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.lastError {
                    errorView(error)
                } else if viewModel.filter != .loginItems && viewModel.services.isEmpty {
                    emptyView
                } else if viewModel.filteredServices.isEmpty {
                    categoryEmptyView
                } else {
                    serviceList
                }
            }
        }
        .alert(
            "startup_delete_confirm_title".localized,
            isPresented: Binding(
                get: { serviceToDelete != nil },
                set: { if !$0 { serviceToDelete = nil } }
            ),
            presenting: serviceToDelete
        ) { service in
            Button("cancel".localized, role: .cancel) {
                serviceToDelete = nil
            }
            Button("startup_delete_action".localized, role: .destructive) {
                let target = service
                let bypassTrash = settings.bypassTrashOnUninstall
                serviceToDelete = nil
                Task { await viewModel.delete(service: target, bypassTrash: bypassTrash) }
            }
        } message: { service in
            Text(String(format: "startup_delete_confirm_message".localized, service.name, service.path))
        }
        .onAppear {
            if settings.enableAI {
                AIExplanationService.shared.prewarm()
            }
            Task { await viewModel.scanIfNeeded() }
        }
    }

    private var filterPicker: some View {
        HStack(spacing: 6) {
            filterButton(title: "startup_filter_all".localized, tag: .all, count: viewModel.services.count)

            filterButton(
                title: "startup_filter_attention".localized,
                tag: .needsAttention,
                count: viewModel.attentionCount,
                icon: "exclamationmark.triangle.fill",
                color: .orange
            )

            Divider().frame(height: 16)

            filterButton(
                title: "startup_category_user".localized,
                tag: .user,
                count: viewModel.userCount,
                icon: ServiceCategory.user.icon,
                color: ServiceCategory.user.color
            )

            filterButton(
                title: "startup_category_third_party".localized,
                tag: .thirdParty,
                count: viewModel.thirdPartyCount,
                icon: ServiceCategory.thirdParty.icon,
                color: ServiceCategory.thirdParty.color
            )

            filterButton(
                title: "startup_category_system".localized,
                tag: .system,
                count: viewModel.systemCount,
                icon: ServiceCategory.system.icon,
                color: ServiceCategory.system.color
            )

            Divider().frame(height: 16)

            filterButton(
                title: "startup_filter_login_items".localized,
                tag: .loginItems,
                count: viewModel.loginItemsCount,
                icon: "person.crop.circle.badge.checkmark",
                color: .purple
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .glassEffect(Glass.regular, in: Capsule())
    }

    private func filterButton(
        title: String,
        tag: StartupFilter,
        count: Int,
        icon: String? = nil,
        color: Color? = nil
    ) -> some View {
        let isSelected = viewModel.filter == tag
        let buttonColor = color ?? Color.accentColor
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.filter = tag
            }
        }) {
            HStack(spacing: 5) {
                if let icon, let color {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white : color)
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(isSelected ? 0.9 : 0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    buttonColor.opacity(0.88),
                                    buttonColor.opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.50), location: 0.0),
                                            .init(color: buttonColor.opacity(0.5), location: 0.5),
                                            .init(color: Color.white.opacity(0.12), location: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: buttonColor.opacity(0.35), radius: 6, x: 0, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var serviceList: some View {
        ScrollView {
            VStack(spacing: 12) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredServices) { service in
                        ServiceRow(
                            service: service,
                            settings: settings,
                            onToggle: {
                                Task { await viewModel.toggle(service: service) }
                            },
                            onDelete: {
                                serviceToDelete = service
                            },
                            onOpenSystemSettings: {
                                Self.openLoginItemsSettings()
                            }
                        )
                        if service.id != viewModel.filteredServices.last?.id {
                            Divider().padding(.leading, 120)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .glassCard()

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("startup_disclaimer".localized)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding()
        }
    }

    static func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: 8) {
                Text("startup_no_agents".localized)
                    .font(.headline)
                Text("startup_no_agents_sub".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryEmptyView: some View {
        VStack(spacing: 16) {
            switch viewModel.filter {
            case .needsAttention:
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundColor(.green)
                    .opacity(0.75)
                VStack(spacing: 8) {
                    Text("startup_attention_empty".localized)
                        .font(.headline)
                    Text("startup_attention_empty_sub".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            case .loginItems:
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundColor(.purple)
                    .opacity(0.7)
                VStack(spacing: 8) {
                    Text(viewModel.loginItemsAccess == .authorizationRequired
                         ? "startup_login_items_restricted".localized
                         : "startup_login_items_empty".localized)
                        .font(.headline)
                    if viewModel.loginItemsAccess == .authorizationRequired {
                        Text("startup_login_items_restricted_sub".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                Button("startup_open_system_settings".localized) {
                    Self.openLoginItemsSettings()
                }
                .secondaryGlassButtonStyle()
            default:
                let category: ServiceCategory? = switch viewModel.filter {
                case .user: .user
                case .thirdParty: .thirdParty
                case .system: .system
                default: nil
                }
                Image(systemName: category?.icon ?? "tray")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundColor(category?.color ?? .secondary)
                    .opacity(0.6)
                VStack(spacing: 8) {
                    Text("startup_category_empty".localized)
                        .font(.headline)
                    if let category {
                        Text(category.helpText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
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
                Text("startup_scan_failed".localized)
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button("try_again".localized) {
                Task { await viewModel.scan() }
            }
            .prominentGlassButtonStyle(tint: .accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ServiceRow: View {
    let service: StartupService
    let settings: AppSettings
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onOpenSystemSettings: () -> Void

    @State private var isExpanded = false
    @State private var aiExplanation = ""
    @State private var verdict: AIExplanationResult.Verdict? = nil
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if service.isLoginItem {
                    LoginItemBadge()
                } else {
                    CategoryBadge(category: service.category)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Text(service.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    FactBadgesRow(service: service)
                }

                Spacer()

                AIExplainButton(isExpanded: isExpanded, isEnabledSetting: settings.enableAI) {
                    withAnimation(.spring()) {
                        isExpanded.toggle()
                    }
                    if isExpanded && aiExplanation.isEmpty && !isGenerating {
                        generateAIExplanation()
                    }
                }

                StatusBadge(isEnabled: service.isEnabled)

                if service.category != .system && !service.requiresRoot {
                    Button(service.isEnabled ? "startup_disable".localized : "startup_enable".localized) {
                        onToggle()
                    }
                    .prominentGlassButtonStyle(tint: service.isEnabled ? .red : .accentColor)
                    .controlSize(.small)
                }

                if FileManager.default.fileExists(atPath: service.path) {
                    Button {
                        let url = URL(fileURLWithPath: service.path)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("startup_show_in_finder".localized)
                }

                if service.isLoginItem || service.requiresRoot {
                    Button {
                        onOpenSystemSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("startup_open_system_settings".localized)
                }

                if !service.isLoginItem && service.category != .system && !service.requiresRoot {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("startup_delete_service".localized)
                }
            }
            .contextMenu {
                if service.category != .system && !service.requiresRoot {
                    Button {
                        onToggle()
                    } label: {
                        Label(
                            service.isEnabled ? "startup_disable".localized : "startup_enable".localized,
                            systemImage: service.isEnabled ? "stop.circle" : "play.circle"
                        )
                    }
                }

                if FileManager.default.fileExists(atPath: service.path) {
                    Button {
                        let url = URL(fileURLWithPath: service.path)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("startup_show_in_finder".localized, systemImage: "folder")
                    }
                }

                if service.isLoginItem || service.requiresRoot {
                    Button {
                        onOpenSystemSettings()
                    } label: {
                        Label("startup_open_system_settings".localized, systemImage: "gearshape")
                    }
                }

                if !service.isLoginItem && service.category != .system && !service.requiresRoot {
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("startup_delete_service".localized, systemImage: "trash")
                    }
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().padding(.vertical, 4)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                            .font(.caption)
                        
                        if let verdict {
                            AIVerdictBadge(verdict: verdict)
                        }
                        
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
                .padding(.leading, 102)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 12)
    }

    private func generateAIExplanation() {
        isGenerating = true
        errorMessage = nil
        
        let lang = settings.language
        Task {
            do {
                let stream = try await AIExplanationService.shared.explainStartupServiceStream(
                    serviceName: service.name,
                    filePath: service.path,
                    category: service.category.displayName,
                    isEnabled: service.isEnabled,
                    language: lang
                )
                
                await MainActor.run {
                    self.aiExplanation = ""
                }
                for try await chunk in stream {
                    await MainActor.run {
                        self.aiExplanation += chunk
                    }
                }
                
                await MainActor.run {
                    let (extractedVerdict, clean) = AIExplanationResult.extractVerdict(from: self.aiExplanation)
                    self.verdict = extractedVerdict
                    self.aiExplanation = clean
                    self.isGenerating = false
                }
            } catch let error as AIError where error == .contextSizeExceeded {
                await MainActor.run {
                    self.aiExplanation = service.category.displayName
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

struct CategoryBadge: View {
    let category: ServiceCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 10, weight: .bold))
            Text(category.displayName)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(category.color.opacity(0.12)))
        .foregroundColor(category.color)
        .help(categoryHelpText)
        .frame(minWidth: 90)
    }

    private var categoryHelpText: String {
        switch category {
        case .user: return "startup_help_user".localized
        case .thirdParty: return "startup_help_third_party".localized
        case .system: return "startup_help_system".localized
        }
    }
}

struct LoginItemBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 10, weight: .bold))
            Text("startup_filter_login_items".localized)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.purple.opacity(0.12)))
        .foregroundColor(.purple)
        .frame(minWidth: 90)
    }
}

struct FactBadgesRow: View {
    let service: StartupService

    var body: some View {
        if hasAnyBadge {
            HStack(spacing: 6) {
                if service.isOrphaned {
                    factBadge("startup_badge_missing_binary".localized, icon: "questionmark.folder.fill", color: .orange)
                } else if let sig = service.signature {
                    signatureBadge(for: sig)
                }

                if service.executableLocation == .temporaryDirectory {
                    factBadge("startup_badge_tmp_location".localized, icon: "exclamationmark.triangle.fill", color: .orange)
                } else if service.executableLocation == .hiddenDirectory {
                    factBadge("startup_badge_hidden_location".localized, icon: "eye.slash.fill", color: .orange)
                }

                if service.requiresRoot {
                    factBadge("startup_badge_requires_root".localized, icon: "lock.fill", color: .secondary)
                }
            }
        }
    }

    private var hasAnyBadge: Bool {
        service.isOrphaned
            || service.signature != nil
            || service.executableLocation != .standard
            || service.requiresRoot
    }

    @ViewBuilder
    private func signatureBadge(for sig: CodeSignatureInfo) -> some View {
        if !sig.isSigned {
            factBadge("startup_badge_unsigned".localized, icon: "xmark.shield.fill", color: .orange)
        } else if !sig.isValid {
            factBadge("startup_badge_invalid_sig".localized, icon: "exclamationmark.shield.fill", color: .red)
        } else if sig.isAppleSigned {
            factBadge("startup_badge_apple".localized, icon: "checkmark.seal.fill", color: .green)
        } else if sig.isAdHoc {
            factBadge("startup_badge_adhoc".localized, icon: "signature", color: .secondary)
        } else {
            let parts = [
                sig.teamID,
                sig.isNotarized ? "startup_badge_notarized".localized : nil
            ].compactMap { $0 }
            let text = parts.isEmpty ? (sig.authority ?? "Signed") : parts.joined(separator: " • ")
            factBadge(text, icon: "checkmark.shield.fill", color: .blue)
                .help([sig.authority, sig.teamID].compactMap { $0 }.joined(separator: " — "))
        }
    }

    private func factBadge(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
        .foregroundColor(color)
    }
}

struct StatusBadge: View {
    let isEnabled: Bool

    var body: some View {
        Text(isEnabled ? "startup_status_loaded".localized : "startup_status_unloaded".localized)
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
    StartupServicesView(settings: AppSettings())
}
