import SwiftUI

public struct CleanupView: View {
    @State private var viewModel: CleanupViewModel
    @State private var showCopiedHint = false
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
            progressView(title: "Scanning System...", subtitle: viewModel.stepTitle)
        case .preview:
            previewListView
        case .executing:
            progressView(title: "Cleaning Up...", subtitle: viewModel.stepTitle)
        case .completed:
            statusView(
                icon: "checkmark.seal.fill",
                iconColor: .green,
                title: "Cleanup Complete",
                subtitle: "Successfully freed \(viewModel.totalFreedMB) MB of disk space.",
                buttonTitle: "Done",
                action: { viewModel.reset() }
            )
        case .failed:
            failedView
        case .cancelled:
            statusView(
                icon: "xmark.circle.fill",
                iconColor: .secondary,
                title: "Cancelled",
                subtitle: "The operation was cancelled by user.",
                buttonTitle: "Back",
                action: { viewModel.reset() }
            )
        }
    }
    
    @ViewBuilder
    private var idleView: some View {
        @Bindable var vm = viewModel
        
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 8) {
                Text("Ready to Clean")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Scan your system to find safe-to-remove caches and temporary files.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Additional Cleanup Options")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                Toggle("Clean Go Module Cache", isOn: $vm.options.cleanModCache)
                Toggle("Clean Maven Local Repository", isOn: $vm.options.cleanMaven)
                Toggle("Clean Project Caches (e.g. .dart_tool)", isOn: $vm.options.cleanProjects)
                Toggle("Clean .DS_Store files", isOn: $vm.options.cleanDSStore)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 40)
            .padding(.top, 10)
            
            Button(action: { viewModel.startScan() }) {
                Text("Start Scan")
                    .fontWeight(.semibold)
                    .frame(width: 150, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
                Text("Cleanup Failed")
                    .font(.title)
                    .fontWeight(.bold)
                
                if let error = viewModel.lastError {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("An error occurred during the cleanup process.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if !viewModel.scriptLogs.isEmpty {
                VStack(alignment: .leading) {
                    Text("Script Logs:")
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
                Text("Try Again")
                    .fontWeight(.semibold)
                    .frame(width: 150, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    private func statusView(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        subtitle: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [iconColor, iconColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: iconColor.opacity(0.3), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: action) {
                Text(buttonTitle)
                    .fontWeight(.semibold)
                    .frame(width: 150, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
            
            if !viewModel.scriptLogs.isEmpty {
                logPanel
            }
        }
    }
    
    private var previewListView: some View {
        @Bindable var vm = viewModel
        return VStack(spacing: 0) {
            List {
                Section(header: 
                    HStack {
                        Text("Recommended for removal")
                        Spacer()
                        Button(viewModel.items.allSatisfy { $0.isSelected } ? "Deselect All" : "Select All") {
                            let allSelected = viewModel.items.allSatisfy { $0.isSelected }
                            viewModel.updateAllSelection(isSelected: !allSelected)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                ) {
                    ForEach(viewModel.items) { item in
                        // Передаем признак раскрытости и действие для переключения
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
                        
                        // Дети (показываем только если категория раскрыта)
                        if !item.children.isEmpty && expandedItems.contains(item.id) {
                            ForEach(item.children) { child in
                                rowView(for: child, isExpanded: false, onToggleExpand: nil)
                                    .padding(.leading, 24)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            
            if !viewModel.scriptLogs.isEmpty {
                Divider()
                logPanel
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug Log (\(viewModel.scriptLogs.count) lines)")
                .font(.caption)
                .foregroundColor(.secondary)
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
                    .padding(6)
                }
                .frame(height: 120)
                .background(Color.black.opacity(0.08))
                .cornerRadius(6)
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
                Text("Selected: \(viewModel.selectedSizeMB) MB")
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            if !viewModel.scriptLogs.isEmpty {
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
                        Text(showCopiedHint ? "Copied!" : "Copy Logs")
                    }
                    .font(.caption)
                    .foregroundColor(showCopiedHint ? .green : .secondary)
                }
            }
            
            Spacer()
            
            if viewModel.state == .preview {
                Button("Reset") {
                    viewModel.reset()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Clean Now") {
                    viewModel.executeCleanup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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
        HStack(spacing: 8) {
            // Чекбокс (отдельный тап-таргет)
            Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundColor(item.isDeletable ? (item.isSelected ? .accentColor : .secondary) : .secondary.opacity(0.3))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    if item.isDeletable {
                        viewModel.toggleSelection(for: item.id)
                    }
                }
            
            // Основная часть строки (шеврон + текст + размер)
            Button(action: {
                onToggleExpand?()
            }) {
                HStack(spacing: 8) {
                    if !item.children.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.system(.subheadline, design: .monospaced))
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
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(onToggleExpand == nil && item.children.isEmpty)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
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
