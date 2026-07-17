import SwiftUI

public struct DiskAnalyzerView: View {
    let settings: AppSettings
    @State private var viewModel = DiskAnalyzerViewModel()
    
    public init(settings: AppSettings) {
        self.settings = settings
    }
    
    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                categoryFilterView
                
                if viewModel.isScanning {
                    scanningView
                } else if viewModel.filteredItems.isEmpty {
                    emptyView
                } else {
                    itemsListView
                }
            }
            .padding()
        }
        .navigationSubtitle(viewModel.currentURL?.path ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("disk_analyzer_scan".localized) {
                    viewModel.selectFolderAndScan()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            if viewModel.rootURL == nil {
                viewModel.startScan(for: FileManager.default.homeDirectoryForCurrentUser)
            }
        }
    }
    
    private var categoryFilterView: some View {
        HStack {
            Spacer()
            GlassEffectContainer(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FileCategory.allCases, id: \.self) { category in
                            categoryFilterButton(for: category)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
            }
            Spacer()
        }
    }

    private static let categoryFilterActiveBlue = Color(red: 0, green: 0.533, blue: 1)

    private func categoryFilterButton(for category: FileCategory) -> some View {
        let isSelected = viewModel.selectedCategory == category

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectedCategory = category
            }
        } label: {
            Text(category.localizedName)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background {
            Capsule().fill(
                isSelected ? Self.categoryFilterActiveBlue : Color.black.opacity(0.16)
            )
        }
        .glassEffect(
            isSelected
                ? Glass.regular.tint(Self.categoryFilterActiveBlue).interactive()
                : Glass.regular,
            in: Capsule()
        )
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
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            if viewModel.items.isEmpty {
                Text("disk_analyzer_empty".localized)
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Text(String(format: "disk_analyzer_category_empty".localized, viewModel.selectedCategory.localizedName))
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var itemsListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.filteredItems) { item in
                    DiskItemRow(item: item, settings: settings, onShowInFinder: {
                        viewModel.showInFinder(item: item)
                    }, onDelete: {
                        viewModel.moveToTrash(item: item)
                    })
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 12)
    }
}

struct DiskItemRow: View {
    let item: DiskItem
    let settings: AppSettings
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
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if item.isDirectory {
                        Text("folder".localized)
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
                    .padding(.trailing, 8)
                
                if isHovered {
                    HStack(spacing: 4) {
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
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
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
        if item.isDirectory {
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
        if item.isDirectory {
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
