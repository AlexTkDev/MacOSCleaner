// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI


struct RootView: View {
    @State private var selectedItem: NavigationItem? = .dashboard
    /// Keep the sidebar visible; hiding `.windowToolbar` on Dashboard used to
    /// collapse NavigationSplitView to detail-only on macOS 26+.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    let cleanupViewModel: CleanupViewModel
    let journal: TransactionJournal
    let appSettings: AppSettings
    @Bindable var permissionsManager: PermissionsManager
    @Binding var availableUpdate: String?

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
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
                .navigationTitle("app_title".localized)
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
            .navigationSplitViewStyle(.balanced)
            
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
            // Keep the window toolbar (sidebar toggle lives there). Only drop the
            // detail title so Dashboard stays chrome-light without collapsing the split.
            content
                .navigationTitle("")
                .toolbar(removing: .title)
        } else {
            content
                .navigationTitle(item.localizedTitle)
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

