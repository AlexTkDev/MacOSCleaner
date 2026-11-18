// Copyright (C) 2026 AlexTkDev
// SPDX-License-Identifier: LicenseRef-MacOSCleaner-GPLv3-Commons-NC
// Licensed under GNU GPLv3 with Commons Clause v1.0 & Non-Commercial Condition (see LICENSE).

import SwiftUI
import OSLog


private let crashLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner", category: "Crash")

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct MacOSCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Note: AppIntents/linkd errors (com.apple.linkd.autoShortcut connection failures)
    // are expected system noise on some macOS versions. They cannot be fixed in app code
    // as they originate from the system's AppIntents framework initialization.
    @Environment(\.openWindow) private var openWindow
    
    private let commandRunner = CommandRunner()
    private let journal = TransactionJournal()
    private let cleanupViewModel: CleanupViewModel
    private let appSettings = AppSettings()
    private let permissionsManager = PermissionsManager()
    private let updateChecker = UpdateChecker()
    private let updatePrompt = UpdatePromptController()
    @State private var availableUpdate: AvailableUpdate? = nil
    @State private var isCheckingForUpdates = false
    
    init() {
        Self.installCrashHandlers()
        
        let engine = CleanupEngine(commandRunner: commandRunner)
        self.cleanupViewModel = CleanupViewModel(engine: engine, journal: journal, settings: appSettings)

        // Register AppShortcuts
        Task {
            MacOSCleanerShortcuts.updateAppShortcutParameters()
        }
    }
    
    private static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let desc = exception.description
            crashLogger.fault("Uncaught exception: \(exception.name.rawValue): \(desc)")
            crashLogger.fault("Stack trace: \(exception.callStackSymbols.joined(separator: "\n"))")
            fflush(stderr)
            abort()
        }
        
        signal(SIGABRT) { _ in
            crashLogger.fault("Received SIGABRT")
            fflush(stderr)
            _exit(1)
        }
        signal(SIGSEGV) { _ in
            crashLogger.fault("Received SIGSEGV")
            fflush(stderr)
            _exit(1)
        }
        signal(SIGBUS) { _ in
            crashLogger.fault("Received SIGBUS")
            fflush(stderr)
            _exit(1)
        }
    }

    var body: some Scene {
        WindowGroup("MacOS Cleaner") {
            RootView(
                cleanupViewModel: cleanupViewModel,
                journal: journal,
                appSettings: appSettings,
                permissionsManager: permissionsManager,
                updatePrompt: updatePrompt,
                availableUpdate: $availableUpdate
            )
            .task {
                if appSettings.automaticallyCheckForUpdates {
                    availableUpdate = await updateChecker.checkForUpdate()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("about_title".localized) {
                    openWindow(id: "about")
                }
                Button(isCheckingForUpdates ? "update.checking".localized : "update.check".localized) {
                    isCheckingForUpdates = true
                    Task { @MainActor in
                        let result = await updateChecker.checkForUpdate()
                        availableUpdate = result
                        isCheckingForUpdates = false
                        
                        let alert = NSAlert()
                        alert.messageText = "update.check".localized
                        if let result {
                            alert.informativeText = String(format: "update.available".localized, result.version)
                            let downloadTitle = result.dmgURL != nil
                                ? "update.download_dmg".localized
                                : "update.download".localized
                            alert.addButton(withTitle: downloadTitle)
                            alert.addButton(withTitle: "cancel".localized)
                            let response = alert.runModal()
                            if response == .alertFirstButtonReturn {
                                UpdatePromptController.open(result)
                            }
                        } else {
                            let accessory = NSHostingView(rootView: UpToDateAlertView())
                            accessory.frame = NSRect(x: 0, y: 0, width: 300, height: 70)
                            alert.accessoryView = accessory
                            alert.addButton(withTitle: "close".localized)
                            alert.runModal()
                        }
                    }
                }
                .disabled(isCheckingForUpdates)
                
                Button("menu_donate".localized) {
                    NSWorkspace.shared.open(UpdateChecker.donateURL)
                }
            }
            
            CommandGroup(after: .appInfo) {
                Button("history_window_title".localized) {
                    openWindow(id: "cleanup-history")
                }
                .keyboardShortcut("y", modifiers: .command)
            }
        }
        
        Window("about_title".localized, id: "about") {
            AboutView(availableUpdate: availableUpdate)
                .applyAppLanguage(appSettings.language)
                .id(appSettings.language)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        Window("history_window_title".localized, id: "cleanup-history") {
            CleanupHistoryView(journal: journal)
                .applyAppLanguage(appSettings.language)
                .id(appSettings.language)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .defaultSize(width: 480, height: 600)
        
        Settings {
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
            .applyAppLanguage(appSettings.language)
            .id(appSettings.language)
        }
    }
}

struct UpToDateAlertView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("update.up_to_date_message".localized)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("update.releases_label".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Link("https://github.com/AlexTkDev/MacOSCleaner/releases", destination: URL(string: "https://github.com/AlexTkDev/MacOSCleaner/releases") ?? UpdateChecker.releasesURL)
                        .font(.system(size: 11))
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("update.website_label".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Link("https://alextkdev.github.io/MacOSCleaner/", destination: URL(string: "https://alextkdev.github.io/MacOSCleaner/") ?? UpdateChecker.releasesURL)
                        .font(.system(size: 11))
                }
            }
        }
        .frame(width: 300, height: 70, alignment: .leading)
    }
}
