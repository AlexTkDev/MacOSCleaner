import SwiftUI

struct RootView: View {
    @State private var selectedItem: NavigationItem? = .dashboard
    let cleanupViewModel: CleanupViewModel
    let journal: TransactionJournal

    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.systemImage)
                }
            }
            .navigationTitle("Cleaner")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            if let selectedItem {
                contentView(for: selectedItem)
            } else {
                Text("Select an item from the sidebar")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private func contentView(for item: NavigationItem) -> some View {
        switch item {
        case .dashboard:
            DashboardView(journal: journal)
        case .cleanup:
            CleanupView(viewModel: cleanupViewModel)
        case .startupServices:
            StartupServicesView()
        case .uninstaller:
            UninstallerView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    let journal = TransactionJournal()
    RootView(
        cleanupViewModel: CleanupViewModel(
            adapter: ShellCleanupAdapter(commandRunner: CommandRunner()),
            journal: journal
        ),
        journal: journal
    )
}