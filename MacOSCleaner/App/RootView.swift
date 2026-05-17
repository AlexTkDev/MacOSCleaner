import SwiftUI

struct RootView: View {
    @State private var selectedItem: NavigationItem? = .dashboard
    let cleanupViewModel: CleanupViewModel

    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.systemImage)
                }
            }
            .navigationTitle("macOS Cleaner")
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            if let selectedItem {
                switch selectedItem {
                case .dashboard:
                    DashboardView()
                case .cleanup:
                    CleanupView(viewModel: cleanupViewModel)
                case .startupServices:
                    StartupServicesView()
                case .uninstaller:
                    UninstallerView()
                case .settings:
                    SettingsView()
                }
            } else {
                Text("Select an item from the sidebar")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    RootView(cleanupViewModel: CleanupViewModel(
        adapter: ShellCleanupAdapter(commandRunner: CommandRunner()),
        journal: TransactionJournal()
    ))
}