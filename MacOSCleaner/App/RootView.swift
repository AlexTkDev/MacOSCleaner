import SwiftUI

struct RootView: View {
    @State private var selectedItem: NavigationItem? = .dashboard
    let cleanupViewModel: CleanupViewModel
    let journal: TransactionJournal
    let appSettings: AppSettings
    @Bindable var permissionsManager: PermissionsManager
    @Binding var availableUpdate: String?

    var body: some View {
        ZStack {
            NavigationSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(NavigationItem.allCases) { item in
                            SidebarItemRow(
                                item: item,
                               isSelected: selectedItem == item,
                               action: {
                                   withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                       selectedItem = item
                                   }
                               }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                }
                .navigationTitle("app_title".localized)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            } detail: {
                Group {
                    if let selectedItem {
                        contentView(for: selectedItem)
                    } else {
                        Text("sidebar_select_item".localized)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 800, minHeight: 600)
                .macOS27ScreenBackground()
            }
            
            GlassOverlayView(manager: GlassOverlayManager.shared)
        }
        .sheet(isPresented: $permissionsManager.showGuidance) {
            PermissionsView(permissionsManager: permissionsManager)
        }
        .onAppear {
            appSettings.applyTheme()
        }
        .task {
            permissionsManager.refresh()
            permissionsManager.showGuidanceIfNeeded()
        }
    }

    @ViewBuilder
    private func contentView(for item: NavigationItem) -> some View {
        switch item {
        case .dashboard:
            DashboardView(journal: journal)
        case .cleanup:
            CleanupView(viewModel: cleanupViewModel)
        case .diskSpace:
            DiskAnalyzerView(settings: appSettings)
        case .processes:
            ProcessesView(settings: appSettings)
        case .startupServices:
            StartupServicesView(settings: appSettings)
        case .uninstaller:
            UninstallerView(settings: appSettings, navigateToCleanup: { selectedItem = .cleanup })
        case .settings:
            SettingsView(
                settings: appSettings,
                permissionsManager: permissionsManager,
                onForget: {
                    Task {
                        try? await journal.clear()
                    }
                },
                availableUpdate: $availableUpdate
            )
        }
    }
}

#Preview {
    let journal = TransactionJournal()
    let settings = AppSettings()
    let commandRunner = CommandRunner()
    RootView(
        cleanupViewModel: CleanupViewModel(
            engine: CleanupEngine(commandRunner: commandRunner),
            journal: journal,
            settings: settings
        ),
        journal: journal,
        appSettings: settings,
        permissionsManager: PermissionsManager(),
        availableUpdate: .constant(nil)
    )
}

struct SidebarItemRow: View {
    let item: NavigationItem
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
                
                Text(item.localizedTitle)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.12))
                            .glassEffect()
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.05))
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
        }
    }
}

