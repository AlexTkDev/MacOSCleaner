// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI


struct RootView: View {
    @State private var selectedItem: NavigationItem = .dashboard
    @Namespace private var navNamespace
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
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color(NSColor.windowBackgroundColor).opacity(0.85)
                .ignoresSafeArea()

            Color.black.opacity(0.20)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .blur(radius: 140)
                        .frame(width: proxy.size.width * 0.75, height: proxy.size.height * 0.75)
                        .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.12)

                    Circle()
                        .fill(Color.purple.opacity(0.06))
                        .blur(radius: 160)
                        .frame(width: proxy.size.width * 0.65, height: proxy.size.height * 0.65)
                        .position(x: proxy.size.width * 0.85, y: proxy.size.height * 0.85)

                    Circle()
                        .fill(Color.cyan.opacity(0.03))
                        .blur(radius: 120)
                        .frame(width: proxy.size.width * 0.45, height: proxy.size.height * 0.45)
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                }
            }
            .ignoresSafeArea()

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
            if appSettings.autoScanOnStartup && cleanupViewModel.state == .idle {
                cleanupViewModel.startScan()
            }
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
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(navGroups.indices, id: \.self) { groupIndex in
                    let group = navGroups[groupIndex]

                    HStack(spacing: 4) {
                        ForEach(group, id: \.self) { item in
                            navButton(for: item)
                        }
                    }

                    if groupIndex < navGroups.count - 1 {
                        Divider()
                            .frame(height: 20)
                            .opacity(0.35)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .glassEffect(Glass.regular, in: Capsule())
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
        }
        .id(appSettings.language)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func navButton(for item: NavigationItem) -> some View {
        let isSelected = selectedItem == item
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedItem = item
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, height: 22)
                // Compact on all locales: label only for the selected item.
                if isSelected {
                    Text(item.localizedTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, isSelected ? 16 : 14)
            .padding(.vertical, 6)
            .frame(minWidth: isSelected ? nil : 52, minHeight: 34)
            .contentShape(Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.88),
                                    Color.accentColor.opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.50), location: 0.0),
                                            .init(color: Color.accentColor.opacity(0.5), location: 0.5),
                                            .init(color: Color.white.opacity(0.12), location: 1.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                        .glassEffectUnion(id: "navSelection", namespace: navNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(item.keyboardKey, modifiers: .command)
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
