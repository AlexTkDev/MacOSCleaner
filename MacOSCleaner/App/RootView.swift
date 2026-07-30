// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI


struct RootView: View {
    @State private var selectedItem: NavigationItem = .dashboard
    let cleanupViewModel: CleanupViewModel
    let journal: TransactionJournal
    let appSettings: AppSettings
    @Bindable var permissionsManager: PermissionsManager
    @Binding var availableUpdate: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topNavigationBar
                
                contentView(for: selectedItem)
                    .navigationTitle("MacOS Cleaner")
                    .navigationSubtitle(selectedItem.localizedSubtitle ?? "")
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            GlassOverlayView(manager: GlassOverlayManager.shared)
        }
        .frame(minWidth: 1024, minHeight: 680)
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

    // MARK: - Navigation Groups
    private let navGroups: [[NavigationItem]] = [
        [.dashboard],
        [.cleanup, .diskSpace, .duplicates, .uninstaller],
        [.processes, .startupServices],
        [.settings]
    ]

    private var topNavigationBar: some View {
        HStack(spacing: 0) {
            ForEach(navGroups.indices, id: \.self) { groupIndex in
                let group = navGroups[groupIndex]

                HStack(spacing: 2) {
                    ForEach(group, id: \.self) { item in
                        navButton(for: item)
                    }
                }

                if groupIndex < navGroups.count - 1 {
                    Divider()
                        .frame(height: 16)
                        .opacity(0.4)
                        .padding(.horizontal, 6)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 14))
        .id(appSettings.language)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func navButton(for item: NavigationItem) -> some View {
        let isSelected = selectedItem == item
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedItem = item
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .regular))
                Text(item.localizedTitle)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.6))
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .glassEffect(Glass.regular.tint(Color.accentColor).interactive(), in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .help(item.localizedTitle)
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
        case .duplicates:
            DuplicatesView()
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

