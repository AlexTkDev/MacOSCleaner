import SwiftUI

public struct CleanupView: View {
    @State private var viewModel: CleanupViewModel
    @State private var showLogs = false
    @State private var showCopiedHint = false
    @State private var logHeight: CGFloat = 160
    @State private var expandedItems: Set<UUID> = []
    @Environment(\.colorScheme) private var colorScheme
    
    public init(viewModel: CleanupViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            footer
        }
        .background(
            ZStack {
                Color(NSColor.windowBackgroundColor)
                if viewModel.state == .scanning || viewModel.state == .executing {
                    LinearGradient(
                        colors: [.accentColor.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        )
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
        
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 12) {
                Text("cleanup_ready".localized)
                    .font(.system(.title, design: .rounded, weight: .bold))
                
                Text("cleanup_ready_sub".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("cleanup_additional_options".localized)
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Toggle("cleanup_option_dev_caches".localized, isOn: $vm.options.cleanDevCaches)
                Text("cleanup_option_dev_caches_sub".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
                
                Toggle("cleanup_option_ds_store".localized, isOn: $vm.options.cleanDSStore)
                Text("cleanup_option_ds_store_sub".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .padding(.top, 10)
            
            Button(action: { viewModel.startScan() }) {
                Text("cleanup_start_scan".localized)
                    .font(.headline)
                    .frame(width: 180, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                    
                    Text(String(format: "cleanup_complete_sub".localized, viewModel.totalFreedMB))
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
                            
                            Text("\(item.freedMB) MB")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                }
                .listStyle(.inset)
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
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(viewModel.currentStep) / CGFloat(max(1, viewModel.totalSteps)), height: 8)
                            .animation(.spring(), value: viewModel.currentStep)
                    }
                }
                .frame(width: 300, height: 8)
            }
            
            if showLogs && !viewModel.scriptLogs.isEmpty {
                Divider()
                logPanel
            }
        }
    }
    
    private var previewListView: some View {
        @Bindable var vm = viewModel
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
                .disabled(viewModel.selectedSizeMB == 0)
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
                    ForEach(viewModel.items) { item in
                        rowView(for: item, isExpanded: expandedItems.contains(item.id)) {
                            if !item.children.isEmpty {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if expandedItems.contains(item.id) {
                                        expandedItems.remove(item.id)
                                    } else {
                                        expandedItems.insert(item.id)
                                    }
                                }
                            }
                        }
                        .listRowBackground(viewModel.selectedItemId == item.id ? Color.accentColor.opacity(0.1) : Color.clear)
                        
                        // Дети (показываем только если категория раскрыта)
                        if !item.children.isEmpty && expandedItems.contains(item.id) {
                            ForEach(item.children) { child in
                                rowView(for: child, isExpanded: false, onToggleExpand: nil)
                                    .padding(.leading, 24)
                                    .listRowBackground(viewModel.selectedItemId == child.id ? Color.accentColor.opacity(0.1) : Color.clear)
                            }
                        }
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
            
            if showLogs && !viewModel.scriptLogs.isEmpty {
                Divider()
                logPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func riskBadge(for risk: OperationRisk) -> some View {
        Text(risk.rawValue.uppercased())
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
                
                Button(action: { showLogs = false }) {
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
            .overlay(
                // Resize Handle Area
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 4)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeUpDown.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let delta = value.location.y - value.startLocation.y
                                logHeight = max(100, min(600, logHeight - delta))
                            }
                    ),
                alignment: .top
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
                .frame(height: logHeight)
                .background(Color.black.opacity(0.12))
                .onChange(of: viewModel.scriptLogs.count) { _, _ in
                    if let last = viewModel.scriptLogs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var footer: some View {
        HStack(spacing: 12) {
            if viewModel.state == .preview {
                Text(String(format: "cleanup_selected".localized, viewModel.selectedSizeMB))
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            if !viewModel.scriptLogs.isEmpty {
                HStack(spacing: 16) {
                    Button(action: { showLogs.toggle() }) {
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
                .keyboardShortcut(.cancelAction)
                
                Button("cleanup_now".localized) {
                    viewModel.executeCleanup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedSizeMB == 0)
            }
        }
        .padding()
        .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
    }
    
    private func rowView(
        for item: CleanupViewModel.CleanupPreviewItem,
        isExpanded: Bool,
        onToggleExpand: (() -> Void)? = nil
    ) -> some View {
        let isSelected = viewModel.selectedItemId == item.id
        
        return HStack(spacing: 8) {
            // Чекбокс (отдельный тап-таргет)
            if item.isDeletable {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(item.isSelected ? .accentColor : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleSelection(for: item.id)
                    }
            } else {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 20, height: 20)
            }
            
            // Основная часть строки (шеврон + текст + размер)
            HStack(spacing: 8) {
                if !item.children.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                        .onTapGesture {
                            onToggleExpand?()
                        }
                } else {
                    Spacer().frame(width: 12)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    riskBadge(for: item.risk)
                }
                
                Spacer()
                
                Text("\(item.sizeMB) MB")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectItem(item.id)
            }
        }
        .padding(.vertical, 4)
    }
}

// Помощник для эффекта размытия (Glassmorphism)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
