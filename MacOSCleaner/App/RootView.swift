import SwiftUI

struct RootView: View {
    @State private var selectedItem: NavigationItem? = .dashboard
    let cleanupViewModel: CleanupViewModel
    let journal: TransactionJournal
    let appSettings: AppSettings
    @Bindable var permissionsManager: PermissionsManager

    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.localizedTitle, systemImage: item.systemImage)
                }
            }
            .navigationTitle("app_title".localized)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            if let selectedItem {
                contentView(for: selectedItem)
                    .frame(minWidth: 900, minHeight: 600)
            } else {
                Text("sidebar_select_item".localized)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }

        .sheet(isPresented: $permissionsManager.showGuidance) {
            PermissionsView(permissionsManager: permissionsManager)
        }
        .onAppear {
            appSettings.applyTheme()
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
        case .processes:
            ProcessesView()
        case .startupServices:
            StartupServicesView()
        case .uninstaller:
            UninstallerView(settings: appSettings)
        case .settings:
            SettingsView(
                settings: appSettings,
                permissionsManager: permissionsManager,
                onForget: {
                    Task {
                        try? await journal.clear()
                    }
                }
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
        permissionsManager: PermissionsManager()
    )
}
