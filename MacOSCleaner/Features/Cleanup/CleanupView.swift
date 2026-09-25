import SwiftUI

public struct CleanupView: View {
    let viewModel: CleanupViewModel
    @State private var showLogs = false
    @State private var showCopiedHint = false
    @State private var scrollTaskBox = ScrollTaskBox()
    @State private var showingFontCacheAlert = false
    
    public init(viewModel: CleanupViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                if viewModel.settings.isDebugMode && showLogs && !viewModel.scriptLogs.isEmpty && viewModel.state != .failed {
                    VSplitView {
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(minHeight: 200)
                        
                        logPanel
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 120, idealHeight: 180, maxHeight: 400)
                    }
                } else {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Divider()
                
                footer
            }
            .background {
                if viewModel.state == .scanning || viewModel.state == .executing {
                    LinearGradient(
                        colors: [.accentColor.opacity(0.08), .accentColor.opacity(0.02), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .onAppear {
            if viewModel.settings.enableAI {
                AIExplanationService.shared.prewarm(promptPrefix: "Cleanup")
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            idleView
        case .scanning:
            progressView(title: "cleanup_scanning".localized, subtitle: viewModel.stepTitle)
        case .preview:
            if viewModel.items.isEmpty {
                statusView(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "cleanup_clean".localized,
                    subtitle: "cleanup_clean_sub".localized,
                    buttonTitle: "cleanup_rescan".localized,
                    action: { viewModel.startScan() }
                )
            } else {
                previewListView
            }
        case .executing:
            progressView(title: "cleanup_cleaning".localized, subtitle: viewModel.stepTitle)
        case .completed:
            completionReportView
        case .failed:
            failedView
        case .cancelled:
            statusView(
                icon: "xmark.circle.fill",
                iconColor: .secondary,
                title: "cancel".localized,
                subtitle: "cancel_description".localized,
                buttonTitle: "close".localized,
                action: { viewModel.reset() }
            )
        }
    }
    
    @ViewBuilder
    private var idleView: some View {
        @Bindable var vm = viewModel

        ScrollView {
            VStack(spacing: 24) {
                // Hero
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.tint)

                        Text("cleanup_ready".localized)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    Text("cleanup_ready_sub".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
                .padding(.top, 16)

                // Central options container
                VStack(alignment: .leading, spacing: 14) {
                    // Section 1: Base cleanup (default, always active)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("cleanup_base_section_title".localized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.8))

                        HStack(spacing: 8) {
                            baseCleanupPill(title: "cleanup_base_system_cache".localized, icon: "internaldrive")
                            baseCleanupPill(title: "cleanup_base_app_logs".localized, icon: "doc.plaintext")
                            baseCleanupPill(title: "cleanup_base_browser_cache".localized, icon: "globe")
                            baseCleanupPill(title: "cleanup_base_trash".localized, icon: "trash", expands: true)
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Section 2: Additional options (2-column compact grid with full-width bottom anchor)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("cleanup_additional_options".localized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.8))

                        let options = additionalOptions(vm: vm)
                        let isOdd = options.count % 2 != 0
                        let gridItems = isOdd ? Array(options.dropLast()) : options
                        let bottomItem = isOdd ? options.last : nil

                        LazyVGrid(columns: additionalOptionsColumns, spacing: 10) {
                            ForEach(gridItems) { item in
                                optionCell(for: item)
                            }
                        }

                        if let bottomItem {
                            optionCell(for: bottomItem)
                        }
                    }
                }
                .padding(16)
                .glassCard(cornerRadius: 12)

                // Start button
                Button(action: { viewModel.startScan() }) {
                    Text("cleanup_start_scan".localized)
                        .font(.headline)
                        .frame(maxWidth: 280)
                        .frame(height: 32)
                }
                .prominentGlassButtonStyle()

                Spacer()
            }
            .frame(maxWidth: 880)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private let additionalOptionsColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private func additionalOptions(vm: CleanupViewModel) -> [CleanupOptionItem] {
        [
            CleanupOptionItem(
                title: "cleanup_option_ds_store".localized,
                subtitle: "cleanup_option_ds_store_sub".localized,
                icon: "doc",
                requiresAdmin: false,
                binding: Binding(
                    get: { vm.options.cleanDSStore },
                    set: { vm.options.cleanDSStore = $0 }
                )
            ),
            CleanupOptionItem(
                title: "cleanup_option_tm_snapshots".localized,
                subtitle: "cleanup_option_tm_snapshots_sub".localized,
                icon: "clock.arrow.circlepath",
                requiresAdmin: true,
                binding: Binding(
                    get: { vm.options.cleanTimeMachineSnapshots },
                    set: { vm.options.cleanTimeMachineSnapshots = $0 }
                )
            ),
            CleanupOptionItem(
                title: "cleanup_option_cloud_docs".localized,
                subtitle: "cleanup_option_cloud_docs_sub".localized,
                icon: "icloud",
                requiresAdmin: false,
                binding: Binding(
                    get: { vm.options.cleanCloudDocs },
                    set: { vm.options.cleanCloudDocs = $0 }
                )
            ),
            CleanupOptionItem(
                title: "cleanup_option_voice_memos".localized,
                subtitle: "cleanup_option_voice_memos_sub".localized,
                icon: "mic",
                requiresAdmin: false,
                binding: Binding(
                    get: { vm.options.cleanVoiceMemos },
                    set: { vm.options.cleanVoiceMemos = $0 }
                )
            ),
            CleanupOptionItem(
                title: "cleanup_option_garageband_logic".localized,
                subtitle: "cleanup_option_garageband_logic_sub".localized,
                icon: "music.note",
                requiresAdmin: false,
                binding: Binding(
                    get: { vm.options.cleanGarageBandLogic },
                    set: { vm.options.cleanGarageBandLogic = $0 }
                )
            ),
            CleanupOptionItem(
                title: "cleanup_option_imovie_final_cut".localized,
                subtitle: "cleanup_option_imovie_final_cut_sub".localized,
                icon: "film",
                requiresAdmin: false,
                binding: Binding(
                    get: { vm.options.cleanIMovieFinalCut },
                    set: { vm.options.cleanIMovieFinalCut = $0 }
                )
            ),
            CleanupOptionItem(
                title: "cleanup_option_font_cache".localized,
                subtitle: "cleanup_option_font_cache_sub".localized,
                icon: "textformat",
                requiresAdmin: false,
                binding: Binding(
                    get: { vm.options.cleanFontCache },
                    set: { vm.options.cleanFontCache = $0 }
                )
            )
        ]
    }

    private func baseCleanupPill(title: String, icon: String, expands: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.green)

            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
                .fixedSize(horizontal: !expands, vertical: false)
        }
        .frame(maxWidth: expands ? .infinity : nil)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .help(title)
    }

    private func optionCell(for item: CleanupOptionItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 15))
                .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if item.requiresAdmin {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("cleanup_badge_password".localized)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.14))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
                        )
                    }
                }

                Text(cleanSubtitle(for: item))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Toggle(isOn: item.binding) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .scaleEffect(0.8)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.isEnabled ? Color.accentColor.opacity(0.06) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(item.isEnabled ? Color.accentColor.opacity(0.20) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            item.binding.wrappedValue.toggle()
        }
    }

    private func cleanSubtitle(for item: CleanupOptionItem) -> String {
        guard item.requiresAdmin else { return item.subtitle }
        return item.subtitle
            .replacingOccurrences(of: " (Requires password).", with: ".")
            .replacingOccurrences(of: " (Requires password)", with: "")
            .replacingOccurrences(of: "(Requires password)", with: "")
            .replacingOccurrences(of: " (требуется пароль).", with: ".")
            .replacingOccurrences(of: " (требуется пароль)", with: "")
            .replacingOccurrences(of: "(требуется пароль)", with: "")
            .replacingOccurrences(of: " (Passwort erforderlich).", with: ".")
            .replacingOccurrences(of: " (Passwort erforderlich)", with: "")
            .replacingOccurrences(of: " (Mot de passe requis).", with: ".")
            .replacingOccurrences(of: " (Mot de passe requis)", with: "")
            .replacingOccurrences(of: " (requiere contraseña).", with: ".")
            .replacingOccurrences(of: " (requiere contraseña)", with: "")
            .replacingOccurrences(of: " (richiede password).", with: ".")
            .replacingOccurrences(of: " (richiede password)", with: "")
            .replacingOccurrences(of: " (パスワードが必要).", with: ".")
            .replacingOccurrences(of: " (パスワードが必要)", with: "")
            .replacingOccurrences(of: " (Requer senha).", with: ".")
            .replacingOccurrences(of: " (Requer senha)", with: "")
            .replacingOccurrences(of: " (потрібен пароль).", with: ".")
            .replacingOccurrences(of: " (потрібен пароль)", with: "")
            .replacingOccurrences(of: "（需要密码）。", with: "。")
            .replacingOccurrences(of: "（需要密码）", with: "")
            .replacingOccurrences(of: " (需要密码)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    @ViewBuilder
    private var failedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, .red.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 8) {
                Text("cleanup_failed".localized)
                    .font(.title)
                    .fontWeight(.bold)
                
                if let error = viewModel.lastError {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("cleanup_failed_default".localized)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if viewModel.settings.isDebugMode && !viewModel.scriptLogs.isEmpty {
                VStack(alignment: .leading) {
                    Text("cleanup_script_logs".localized)
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(viewModel.scriptLogs.suffix(50).enumerated()), id: \.offset) { _, log in
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 150)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 40)
            }
            
            Button(action: { viewModel.reset() }) {
                Text("try_again".localized)
                    .fontWeight(.semibold)
                    .frame(width: 150)
            }
            .prominentGlassButtonStyle(tint: .accentColor)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    @ViewBuilder
    private var completionReportView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.green)
                }
                
                VStack(spacing: 8) {
                    Text("cleanup_complete".localized)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    
                    Text(String(format: "cleanup_complete_sub".localized, viewModel.totalFreedBytes.formattedByteCount()))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("cleanup_summary".localized)
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 16)
                
                List {
                    ForEach(viewModel.cleanedItems) { item in
                        HStack {
                            Text(item.label)
                                .font(.system(.subheadline, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Text(item.freedBytes.formattedByteCount())
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                }
                .listStyle(.inset)
                
                if !viewModel.skippedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("cleanup_skipped".localized)
                            .font(.headline)
                            .foregroundColor(.orange)
                            .padding(.top, 8)
                        
                        ForEach(viewModel.skippedItems) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.system(.subheadline, design: .monospaced))
                                    Text(item.reason)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            
            Spacer()
            
            Button(action: { viewModel.reset() }) {
                Text("done".localized)
                    .fontWeight(.semibold)
                    .frame(width: 150)
            }
            .prominentGlassButtonStyle(tint: .accentColor)
            .padding(.bottom, 40)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private func statusView(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        subtitle: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(iconColor)
            }
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            
            Button(action: action) {
                Text(buttonTitle)
                    .fontWeight(.semibold)
                    .frame(width: 150)
            }
            .prominentGlassButtonStyle(tint: .accentColor)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private func progressView(title: String, subtitle: String) -> some View {
        VStack(spacing: 20) {
            AnimatedScanView(
                title: title,
                subtitle: subtitle,
                currentStep: viewModel.currentStep,
                totalSteps: viewModel.totalSteps,
                onCancel: { viewModel.cancel() }
            )
        }
        .padding(.top, 20)
    }
    
    private var previewListView: some View {
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("cleanup_scan_results".localized)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("cleanup_scan_results_sub".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button(action: { viewModel.startScan() }) {
                    Label("cleanup_rescan".localized, systemImage: "arrow.clockwise")
                        .fontWeight(.medium)
                }
                .glassButtonStyle()
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            List {
                Section(header:
                    HStack {
                        Text("cleanup_recommended".localized)
                        Spacer()
                        Button(viewModel.items.allSatisfy { $0.isSelected } ? "cleanup_deselect_all".localized : "cleanup_select_all".localized) {
                            let allSelected = viewModel.items.allSatisfy { $0.isSelected }
                            viewModel.updateAllSelection(isSelected: !allSelected)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                ) {
                    ForEach(viewModel.items) { category in
                        categoryDisclosureGroup(for: category)
                    }
                }
            }
            .listStyle(.inset)

            if let selected = viewModel.selectedItem, let desc = selected.description {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("cleanup_manual_instructions".localized)
                                .font(.headline)
                        }
                        Spacer()
                        Button(action: { viewModel.selectedItemId = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(NSColor.separatorColor)),
                    alignment: .top
                )
            }
        }
    }

    // MARK: - Category Row

    private func categoryRow(_ category: CleanupPreviewItem) -> some View {
        HStack(spacing: 8) {
            if category.isDeletable {
                Image(systemName: category.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(category.isSelected ? .accentColor : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleSelection(for: category.id)
                    }
            } else {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 20, height: 20)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(category.label)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundColor(.primary)
                        if isDevCategory(category.category) {
                            devCacheBadge()
                        }
                    }
                    riskBadge(for: category.risk)
                }

                Spacer()

                Text(category.sizeBytes.formattedByteCount())
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.toggleCategoryExpansion(category.id)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Category DisclosureGroup

    private func categoryDisclosureGroup(for category: CleanupPreviewItem) -> some View {
        let isExpanded = viewModel.isExpanded(category.id)
        return DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { _ in viewModel.toggleCategoryExpansion(category.id) }
        )) {
            ForEach(viewModel.visibleItems(for: category.id)) { item in
                CleanupFileRow(item: item, settings: viewModel.settings) {
                    viewModel.toggleSelection(for: item.id)
                }
                .padding(.leading, 8)
            }
            if viewModel.hasMoreItems(category.id) {
                Button {
                    viewModel.showAllItems(category.id)
                } label: {
                    Text(String(format: "cleanup_show_all_count".localized, viewModel.remainingCount(category.id)))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .padding(.leading, 32)
                .padding(.vertical, 4)
            }
        } label: {
            categoryRow(category)
        }
        .listRowBackground(
            viewModel.selectedItemId == category.id
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
    }

    // MARK: - Risk Badge
    private func riskBadge(for risk: OperationRisk) -> some View {
        Text(risk.localizedTitle.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor(for: risk).opacity(0.15))
            .foregroundColor(riskColor(for: risk))
            .cornerRadius(4)
    }
    
    private func riskColor(for risk: OperationRisk) -> Color {
        switch risk {
        case .safe: return .green
        case .moderate: return .orange
        case .dangerous: return .red
        case .protected: return .secondary
        }
    }

    private func devCacheBadge() -> some View {
        Text("cleanup_dev_badge".localized)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15))
            .foregroundColor(.purple)
            .cornerRadius(4)
    }

    private func isDevCategory(_ category: String?) -> Bool {
        guard let category else { return false }
        return ["gradle_maven", "flutter_dart", "xcode", "android_caches",
                "android_sdk", "ide_caches", "language_caches",
                "swift_pm_cache", "carthage_cache"].contains(category)
    }
    
    @ViewBuilder
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Resize handle & Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                    Text(String(format: "cleanup_debug_log".localized, viewModel.scriptLogs.count))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLogs = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.scriptLogs.enumerated()), id: \.offset) { idx, log in
                            Text(log)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(log.hasPrefix("[stderr]") ? .red :
                                                 log.hasPrefix("[debug]") ? .orange : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .background(Color.black.opacity(0.12))
                .onChange(of: viewModel.scriptLogs.count) { _, _ in
                    scrollTaskBox.task?.cancel()
                    scrollTaskBox.task = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled else { return }
                        if let last = viewModel.scriptLogs.indices.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var footer: some View {
        HStack(spacing: 16) {
            if viewModel.state == .preview {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 13, weight: .bold))
                    Text(String(format: "cleanup_selected".localized, viewModel.selectedSizeBytes.formattedByteCount(forceGB: true)))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
            }
            
            if viewModel.settings.isDebugMode && !viewModel.scriptLogs.isEmpty {
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLogs.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showLogs ? "chevron.down.square" : "chevron.up.square")
                            Text(showLogs ? "cleanup_hide_logs".localized : "cleanup_show_logs".localized)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        let text = viewModel.scriptLogs.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        
                        withAnimation {
                            showCopiedHint = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showCopiedHint = false
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedHint ? "checkmark.circle.fill" : "doc.on.clipboard")
                            Text(showCopiedHint ? "cleanup_copy_logs".localized : "cleanup_copy".localized)
                        }
                        .font(.caption)
                        .foregroundColor(showCopiedHint ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            if viewModel.state == .preview {
                Button("reset".localized) {
                    viewModel.reset()
                }
                .glassButtonStyle()
                .keyboardShortcut(.cancelAction)
                
                Button(action: {
                    if viewModel.isFontCacheSelectedForCleanup {
                        showingFontCacheAlert = true
                    } else {
                        viewModel.executeCleanup()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("cleanup_now".localized)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 8)
                }
                .prominentGlassButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedSizeBytes == 0)
                .alert("cleanup_font_cache_confirm_title".localized, isPresented: $showingFontCacheAlert) {
                    Button("cleanup_font_cache_confirm_action".localized, role: .destructive) {
                        viewModel.executeCleanup()
                    }
                    Button("cancel".localized, role: .cancel) {}
                } message: {
                    Text("cleanup_font_cache_confirm_message".localized)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect()
    }
}

struct CleanupFileRow: View {
    let item: CleanupPreviewItem
    let settings: AppSettings
    let onToggleSelection: () -> Void

    @State private var isExpanded = false
    @State private var aiExplanation = ""
    @State private var verdict: AIExplanationResult.Verdict? = nil
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if item.isDeletable {
                    Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(item.isSelected ? .accentColor : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onToggleSelection()
                        }
                } else {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.path ?? item.label)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let date = item.modificationDate {
                        Text(date.formatted(.dateTime.day().month().year().locale(LanguageManager.shared.currentLocale)))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let path = item.path {
                    Button {
                        let resolvedPath = (path as NSString).expandingTildeInPath
                        let url = URL(fileURLWithPath: resolvedPath)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("uninstaller_show_in_finder".localized)
                }

                if let path = item.path {
                    AIExplainButton(isExpanded: isExpanded, isEnabledSetting: settings.enableAI) {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                        }
                        if isExpanded && aiExplanation.isEmpty && !isGenerating {
                            generateAIExplanation(path: path)
                        }
                    }
                }

                Text(item.sizeBytes.formattedByteCount())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            
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
                                ProgressView().controlSize(.small).frame(width: 16, height: 16)
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
                .padding(.leading, 26)
                .padding(.bottom, 4)
            }
        }
    }

    private func generateAIExplanation(path: String) {
        isGenerating = true
        errorMessage = nil
        
        let lang = settings.language
        Task {
            do {
                let stream = try await AIExplanationService.shared.explainCleanupFileStream(
                    fileName: item.label,
                    filePath: path,
                    category: item.category ?? "Cache/Temporary Data",
                    sizeFormatted: item.sizeBytes.formattedByteCount(),
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
                    self.aiExplanation = item.category ?? item.label
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

private final class ScrollTaskBox {
    var task: Task<Void, Never>?
}

public struct CleanupOptionItem: Identifiable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let icon: String
    public let requiresAdmin: Bool
    public var binding: Binding<Bool>

    public var isEnabled: Bool {
        get { binding.wrappedValue }
        nonmutating set { binding.wrappedValue = newValue }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        icon: String,
        requiresAdmin: Bool = false,
        binding: Binding<Bool>
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.requiresAdmin = requiresAdmin
        self.binding = binding
    }

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        icon: String,
        requiresAdmin: Bool = false,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.requiresAdmin = requiresAdmin
        var state = isEnabled
        self.binding = Binding(get: { state }, set: { state = $0 })
    }
}
