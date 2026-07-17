import SwiftUI

public struct CleanupView: View {
    let viewModel: CleanupViewModel
    @State private var showLogs = false
    @State private var showCopiedHint = false
    @State private var scrollTaskBox = ScrollTaskBox()
    
    public init(viewModel: CleanupViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                if showLogs && !viewModel.scriptLogs.isEmpty && viewModel.state != .failed {
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
            VStack(spacing: 28) {
                // Hero
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.tint)
                    
                    VStack(spacing: 6) {
                        Text("cleanup_ready".localized)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("cleanup_ready_sub".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }
                }
                .padding(.top, 40)
                
                // Options card
                VStack(alignment: .leading, spacing: 16) {
                    Text("cleanup_additional_options".localized)
                        .font(.headline)
                    
                    optionToggle(
                        title: "cleanup_option_ds_store".localized,
                        subtitle: "cleanup_option_ds_store_sub".localized,
                        value: $vm.options.cleanDSStore
                    )
                    
                    DisclosureGroup("cleanup_extended_title".localized) {
                        VStack(alignment: .leading, spacing: 14) {
                            optionToggle(
                                title: "cleanup_option_cloud_docs".localized,
                                subtitle: "cleanup_option_cloud_docs_sub".localized,
                                value: $vm.options.cleanCloudDocs
                            )
                            optionToggle(
                                title: "cleanup_option_voice_memos".localized,
                                subtitle: "cleanup_option_voice_memos_sub".localized,
                                value: $vm.options.cleanVoiceMemos
                            )
                            optionToggle(
                                title: "cleanup_option_garageband_logic".localized,
                                subtitle: "cleanup_option_garageband_logic_sub".localized,
                                value: $vm.options.cleanGarageBandLogic
                            )
                            optionToggle(
                                title: "cleanup_option_imovie_final_cut".localized,
                                subtitle: "cleanup_option_imovie_final_cut_sub".localized,
                                value: $vm.options.cleanIMovieFinalCut
                            )
                            optionToggle(
                                title: "cleanup_option_sleep_image".localized,
                                subtitle: "cleanup_option_sleep_image_sub".localized,
                                value: $vm.options.cleanSleepImage
                            )
                        }
                        .padding(.leading, 4)
                        .padding(.top, 8)
                    }
                }
                .padding()
                .glassCard(cornerRadius: 12)
                .padding(.horizontal, 32)
                
                // Start button
                Button(action: { viewModel.startScan() }) {
                    Text("cleanup_start_scan".localized)
                        .font(.headline)
                        .frame(maxWidth: 280)
                        .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func optionToggle(title: String, subtitle: String, value: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle(isOn: value) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.small)
        }
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
            
            if !viewModel.scriptLogs.isEmpty {
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
                    .frame(width: 150, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                    .frame(width: 150, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
            HStack {
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
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: { viewModel.executeCleanup() }) {
                    Text("cleanup_now".localized)
                        .fontWeight(.bold)
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.selectedSizeBytes == 0)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

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
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
        HStack(spacing: 12) {
            if viewModel.state == .preview {
                Text(String(format: "cleanup_selected".localized, viewModel.selectedSizeBytes.formattedByteCount(forceGB: true)))
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            if !viewModel.scriptLogs.isEmpty {
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
                
                Button("cleanup_now".localized) {
                    viewModel.executeCleanup()
                }
                .glassButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedSizeBytes == 0)
            }
        }
        .padding()
        .glassEffect()
    }
}

struct CleanupFileRow: View {
    let item: CleanupPreviewItem
    let settings: AppSettings
    let onToggleSelection: () -> Void

    @State private var isExpanded = false
    @State private var aiExplanation = ""
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

                if settings.enableAI && AIExplanationService.shared.isAvailable, let path = item.path {
                    Button {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                        }
                        if isExpanded && aiExplanation.isEmpty && !isGenerating {
                            generateAIExplanation(path: path)
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundColor(isExpanded ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("uninstaller_explain_with_ai".localized)
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
                let result = try await AIExplanationService.shared.explainCleanupFile(
                    fileName: item.label,
                    filePath: path,
                    category: item.category ?? "Cache/Temporary Data",
                    sizeFormatted: item.sizeBytes.formattedByteCount(),
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

private final class ScrollTaskBox {
    var task: Task<Void, Never>?
}
