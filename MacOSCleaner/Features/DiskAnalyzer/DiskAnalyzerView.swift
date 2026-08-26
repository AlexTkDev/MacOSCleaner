import SwiftUI
import QuickLook

public struct DiskAnalyzerView: View {
    let settings: AppSettings
    @State private var viewModel = DiskAnalyzerViewModel()
    
    public init(settings: AppSettings) {
        self.settings = settings
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            headerControlsView
            
            if !viewModel.isScanning && viewModel.currentItem != nil {
                breadcrumbsView
            }
            
            if viewModel.isScanning {
                scanningView
            } else if viewModel.displayedItems.isEmpty {
                emptyView
            } else {
                itemsListView
            }
        }
        .padding(16)
        .quickLookPreview($viewModel.quickLookURL)
        .onAppear {
            if viewModel.rootURL == nil {
                viewModel.startScan(for: FileManager.default.homeDirectoryForCurrentUser)
            }
        }
    }
    
    private var headerControlsView: some View {
        HStack(spacing: 12) {
            // Folder Selector Menu
            Menu {
                Button(action: { viewModel.startScan(for: FileManager.default.homeDirectoryForCurrentUser) }) {
                    Label("duplicate_folder_home".localized, systemImage: "house")
                }
                Button(action: { viewModel.startScan(for: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!) }) {
                    Label("duplicate_folder_downloads".localized, systemImage: "arrow.down.circle")
                }
                Button(action: { viewModel.startScan(for: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!) }) {
                    Label("duplicate_folder_documents".localized, systemImage: "doc")
                }
                Divider()
                Button(action: { viewModel.selectFolderAndScan() }) {
                    Label("duplicate_folder_custom".localized, systemImage: "folder.badge.plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(viewModel.rootURL?.lastPathComponent ?? FileManager.default.homeDirectoryForCurrentUser.lastPathComponent)
                        .lineLimit(1)
                }
            }

            Spacer()

            categoryFilterView

            Spacer()

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("settings_search_prompt".localized, text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 140)
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Scan Action Button
            Button(action: { viewModel.selectFolderAndScan() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("disk_analyzer_scan".localized)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var categoryFilterView: some View {
        GlassPillPicker(
            items: FileCategory.allCases,
            selection: $viewModel.selectedCategory,
            label: { $0.localizedName }
        )
    }
    
    private var breadcrumbsView: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.navigateUp()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canNavigateUp)
            .opacity(viewModel.canNavigateUp ? 1.0 : 0.3)
            .help("disk_analyzer_back".localized)
            
            Divider()
                .frame(height: 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(viewModel.pathTrail.enumerated()), id: \.element.id) { index, item in
                        let isLast = index == viewModel.pathTrail.count - 1
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.navigateTo(item: item)
                            }
                        }) {
                            HStack(spacing: 4) {
                                if index == 0 {
                                    Image(systemName: "house.fill")
                                        .font(.caption)
                                }
                                Text(item.name.isEmpty ? "/" : item.name)
                                    .font(.callout.weight(isLast ? .semibold : .regular))
                                    .foregroundColor(isLast ? .primary : .secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isLast ? Color.primary.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        
                        if !isLast {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            
            Spacer()
            
            if let current = viewModel.currentItem {
                HStack(spacing: 8) {
                    let count = viewModel.selectedCategory == .all ? current.fileCount : viewModel.displayedItems.count
                    Text(String(format: "disk_analyzer_items_count".localized, count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    let totalSize = viewModel.selectedCategory == .all ? current.size : viewModel.displayedItems.reduce(0) { $0 + $1.size }
                    Text(totalSize.formattedByteCount())
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            LiquidGlassLoaderView(size: 56)
            
            Text("disk_analyzer_scanning".localized)
                .font(.headline)
            
            if !viewModel.currentScanningName.isEmpty {
                Text(viewModel.currentScanningName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
            if viewModel.displayedItems.isEmpty {
                if viewModel.selectedCategory != .all {
                    Text(String(format: "disk_analyzer_category_empty".localized, viewModel.selectedCategory.localizedName))
                        .font(.headline)
                        .foregroundColor(.secondary)
                } else {
                    Text("disk_analyzer_empty".localized)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var itemsListView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.displayedItems) { item in
                    let isSelected = viewModel.selectedItem?.id == item.id
                    DiskItemRow(
                        item: item,
                        isSelected: isSelected,
                        settings: settings,
                        onDrillDown: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.drillDown(into: item)
                            }
                        },
                        onQuickLook: {
                            viewModel.toggleQuickLook(for: item)
                        },
                        onShowInFinder: {
                            viewModel.showInFinder(item: item)
                        },
                        onDelete: {
                            viewModel.moveToTrash(item: item)
                        }
                    )
                    .onTapGesture {
                        if item.isDirectory && !item.isPackage {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.drillDown(into: item)
                            }
                        } else {
                            viewModel.selectedItem = item
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct DiskItemRow: View {
    let item: DiskItem
    let isSelected: Bool
    let settings: AppSettings
    let onDrillDown: () -> Void
    let onQuickLook: () -> Void
    let onShowInFinder: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    @State private var isExpanded = false
    @State private var aiExplanation = ""
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.body.weight(item.isDirectory && !item.isPackage ? .medium : .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        if item.isDirectory && !item.isPackage {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    
                    if item.isDirectory && !item.isPackage {
                        Text(String(format: "disk_analyzer_items_count".localized, item.fileCount))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(item.url.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
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
                
                Text(item.size.formattedByteCount())
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
                
                if isHovered || isSelected {
                    HStack(spacing: 4) {
                        if !item.isDirectory || item.isPackage {
                            Button(action: onQuickLook) {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.plain)
                            .help("disk_analyzer_quick_look".localized)
                        }
                        
                        if item.isDirectory && !item.isPackage {
                            Button(action: onDrillDown) {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.plain)
                            .help("disk_analyzer_open_folder".localized)
                        }
                        
                        Button(action: onShowInFinder) {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.plain)
                        .help("disk_analyzer_show_in_finder".localized)
                        
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("disk_analyzer_move_to_trash".localized)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovered = hover
                }
            }
            .confirmationDialog(
                "disk_analyzer_delete_confirm".localized,
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("delete_action".localized, role: .destructive) {
                    onDelete()
                }
                Button("cancel".localized, role: .cancel) {}
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
                .padding(.leading, 36)
                .padding(.bottom, 4)
            }
        }
    }
    
    private func generateAIExplanation() {
        isGenerating = true
        errorMessage = nil
        
        let lang = settings.language
        Task {
            do {
                let result = try await AIExplanationService.shared.explainDiskFile(
                    fileName: item.name,
                    filePath: item.url.path,
                    sizeFormatted: item.size.formattedByteCount(),
                    fileType: item.fileType.localizedName,
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
    
    private var iconName: String {
        if item.isDirectory && !item.isPackage {
            return "folder.fill"
        }
        switch item.fileType {
        case .video: return "play.rectangle.fill"
        case .audio: return "music.note"
        case .photo: return "photo.fill"
        case .apps: return "app.badge.fill"
        case .docs: return "doc.text.fill"
        case .archives: return "doc.zipper"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        if item.isDirectory && !item.isPackage {
            return .blue
        }
        switch item.fileType {
        case .video: return .purple
        case .audio: return .pink
        case .photo: return .cyan
        case .apps: return .orange
        case .docs: return .green
        case .archives: return .yellow
        default: return .secondary
        }
    }
}

