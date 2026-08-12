// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI


struct RootView: View {
    @State private var selectedItem: NavigationItem = .dashboard
    let cleanupViewModel: CleanupViewModel
    let journal: TransactionJournal
    let appSettings: AppSettings
    @Bindable var permissionsManager: PermissionsManager
    @Bindable var updatePrompt: UpdatePromptController
    @Binding var availableUpdate: AvailableUpdate?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "version_unknown".localized
    }

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
                    // Recreate screen content so every `.localized` string / glass layer
                    // matches the selected language (prevents stale RU labels in EN/FR/…).
                    .id(appSettings.language)
            }
            
            GlassOverlayView(manager: GlassOverlayManager.shared)
        }
        .frame(minWidth: 1024, minHeight: 680)
        .environment(\.locale, appSettings.language.locale)
        .sheet(isPresented: $permissionsManager.showGuidance) {
            PermissionsView(permissionsManager: permissionsManager)
        }
        .sheet(isPresented: $updatePrompt.showSheet) {
            if let update = availableUpdate {
                UpdateAvailableView(
                    update: update,
                    currentVersion: currentVersion,
                    onDismissLater: { updatePrompt.dismissTemporarily() },
                    onDismissForVersion: { updatePrompt.dismissForVersion(update.version) }
                )
            }
        }
        .onAppear {
            appSettings.applyTheme()
        }
        .task {
            permissionsManager.refresh()
            permissionsManager.showGuidanceIfNeeded()
            presentUpdateIfReady()
        }
        .onChange(of: availableUpdate) { _, _ in
            presentUpdateIfReady()
        }
        .onChange(of: permissionsManager.showGuidance) { _, showing in
            if !showing {
                presentUpdateIfReady()
            }
        }
    }

    private func presentUpdateIfReady() {
        updatePrompt.presentIfNeeded(
            update: availableUpdate,
            fdaShowing: permissionsManager.showGuidance
        )
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
                        .frame(height: 18)
                        .opacity(0.4)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 12))
        .id(appSettings.language)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func navButton(for item: NavigationItem) -> some View {
        let isSelected = selectedItem == item
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedItem = item
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, height: 22)
                // Compact on all locales: label only for the selected item.
                if isSelected {
                    Text(item.localizedTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, isSelected ? 10 : 9)
            .padding(.vertical, 6)
            .frame(minWidth: isSelected ? nil : 40, minHeight: 32)
            .contentShape(Rectangle())
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
        updatePrompt: UpdatePromptController(),
        availableUpdate: .constant(nil)
    )
}
