import SwiftUI

public struct DiskAnalyzerView: View {
    @State private var viewModel = DiskAnalyzerViewModel()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public init() {}
    
    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                headerView
                
                categoryFilterView
                
                if viewModel.isScanning {
                    scanningView
                } else if viewModel.items.isEmpty {
                    emptyView
                } else {
                    itemsListView
                }
            }
            .padding()
        }
        .onAppear {
            if viewModel.rootURL == nil {
                viewModel.startScan(for: FileManager.default.homeDirectoryForCurrentUser)
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            if !viewModel.pathStack.isEmpty {
                Button(action: {
                    withAnimation {
                        viewModel.navigateBack()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.secondary.opacity(0.2)))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("disk_analyzer_title".localized)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let currentURL = viewModel.currentURL {
                    Text(currentURL.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            
            Spacer()
            
            Button("disk_analyzer_scan".localized) {
                viewModel.selectFolderAndScan()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 4)
    }
    
    private var categoryFilterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FileCategory.allCases, id: \.self) { category in
                    Button(action: {
                        withAnimation {
                            viewModel.selectedCategory = category
                        }
                    }) {
                        Text(category.localizedName)
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(viewModel.selectedCategory == category ? .accentColor : nil)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            
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
            
            Text("disk_analyzer_empty".localized)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var itemsListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.filteredItems) { item in
                    DiskItemRow(item: item, onNavigate: {
                        withAnimation {
                            viewModel.navigateTo(item: item)
                        }
                    }, onShowInFinder: {
                        viewModel.showInFinder(item: item)
                    }, onDelete: {
                        viewModel.moveToTrash(item: item)
                    })
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(reduceTransparency ? 1.0 : 0.2))
        )
    }
}

struct DiskItemRow: View {
    let item: DiskItem
    let onNavigate: () -> Void
    let onShowInFinder: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
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
                }
            }
            
            Spacer()
            
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
        .onTapGesture {
            if item.isDirectory {
                onNavigate()
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
    }
    
    private var iconName: String {
        if item.isDirectory {
            return "folder.fill"
        }
        switch item.fileType {
        case .video: return "play.rectangle.fill"
        case .audio: return "music.note"
        case .apps: return "app.badge.fill"
        case .docs: return "doc.text.fill"
        case .archives: return "doc.zip.fill"
        case .dev: return "curlybraces"
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
        case .apps: return .orange
        case .docs: return .green
        case .archives: return .yellow
        case .dev: return .teal
        default: return .secondary
        }
    }
}
