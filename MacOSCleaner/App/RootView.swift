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
                List(selection: $selectedItem) {
                    ForEach(SidebarSection.all) { section in
                        Section {
                            ForEach(section.items) { item in
                                Label(item.localizedTitle, systemImage: item.systemImage)
                                    .tag(item)
                            }
                        } header: {
                            if let titleKey = section.titleKey {
                                Text(titleKey.localized)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } detail: {
                Group {
                    if let selectedItem {
                        contentView(for: selectedItem)
                            .modifier(ScreenNavigationTitleModifier(item: selectedItem))
                    } else {
                        Text("sidebar_select_item".localized)
                            .foregroundColor(.secondary)
                    }
                }
                .scrollEdgeEffectStyle(.hard, for: .top)
                .frame(minWidth: 800, minHeight: 600)
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

private struct ScreenNavigationTitleModifier: ViewModifier {
    let item: NavigationItem

    func body(content: Content) -> some View {
        if item == .dashboard {
            content
                .navigationTitle("")
                .toolbar(removing: .title)
                .toolbarVisibility(.hidden, for: .windowToolbar)
        } else {
            content
                .navigationTitle(item.localizedTitle)
                .toolbarVisibility(.visible, for: .windowToolbar)
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

