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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "version_unknown".localized
    }

    var body: some View {
        ZStack {
            windowBackground

            HStack(spacing: 0) {
                NavigationRailView(selectedItem: $selectedItem)
                    .id(appSettings.language)

                railDivider

                VStack(spacing: 0) {
                    windowTitleBar

                    contentView(for: selectedItem)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Recreate screen content so every `.localized` string matches the selected language.
                        .id(appSettings.language)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .overlayPreferenceValue(NavRailHoverPreferenceKey.self) { target in
                GeometryReader { proxy in
                    if let target {
                        let rect = proxy[target.anchor]
                        NavRailTooltipLabel(title: target.item.localizedTitle)
                            .frame(height: 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 56)
                            .offset(y: rect.midY)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .scale(scale: 0.92, anchor: .leading).combined(with: .opacity)
                            )
                            .animation(.easeInOut(duration: 0.12), value: target.item)
                    }
                }
                .allowsHitTesting(false)
                .zIndex(999)
            }

            GlassOverlayView(manager: GlassOverlayManager.shared)
        }
        .frame(minWidth: 1024, minHeight: 680)
        .applyAppLanguage(appSettings.language)
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

    // MARK: - Background & Rail Divider

    @ViewBuilder
    private var windowBackground: some View {
        if reduceTransparency {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
        } else {
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()

                Color(NSColor.windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.85 : 0.90)
                    .ignoresSafeArea()

                if colorScheme == .dark {
                    Color.black.opacity(0.20)
                        .ignoresSafeArea()
                }

                GeometryReader { proxy in
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05))
                            .blur(radius: 140)
                            .frame(width: proxy.size.width * 0.75, height: proxy.size.height * 0.75)
                            .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.12)

                        Circle()
                            .fill(Color.purple.opacity(colorScheme == .dark ? 0.06 : 0.03))
                            .blur(radius: 160)
                            .frame(width: proxy.size.width * 0.65, height: proxy.size.height * 0.65)
                            .position(x: proxy.size.width * 0.85, y: proxy.size.height * 0.85)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var windowTitleBar: some View {
        HStack(spacing: 8) {
            Text(selectedItem.localizedTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, layoutDirection == .leftToRight ? 38 : 20)
        .padding(.trailing, layoutDirection == .leftToRight ? 20 : 38)
        .frame(height: 36)
        .background(WindowDragArea())
    }

    private var railDivider: some View {
        let baseColor = colorScheme == .dark ? Color.white : Color.primary
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.055),
                .init(color: baseColor.opacity(0.08), location: 0.085),
                .init(color: baseColor.opacity(0.08), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        .ignoresSafeArea(.container, edges: .top)
    }


    @ViewBuilder
    private func contentView(for item: NavigationItem) -> some View {
        switch item {
        case .dashboard:
            DashboardView(journal: journal)
        case .cleanup:
            CleanupView(
                viewModel: cleanupViewModel,
                scanLimited: !permissionsManager.hasFullDiskAccess
            )
        case .diskSpace:
            DiskAnalyzerView(settings: appSettings)
        case .duplicates:
            DuplicatesView(settings: appSettings)
        case .processes:
            ProcessesView(settings: appSettings)
        case .startupServices:
            StartupServicesView(settings: appSettings)
        case .uninstaller:
            UninstallerView(
                settings: appSettings,
                navigateToCleanup: { selectedItem = .cleanup },
                scanLimited: !permissionsManager.hasFullDiskAccess
            )
        case .settings:
            SettingsView(
                settings: appSettings,
                permissionsManager: permissionsManager,
                onForget: {
                    Task {
                        await appSettings.resetAllAppData(journal: journal)
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
