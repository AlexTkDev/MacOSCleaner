import SwiftUI

@main
struct MacOSCleanerApp: App {
    // Note: AppIntents/linkd errors (com.apple.linkd.autoShortcut connection failures)
    // are expected system noise on some macOS versions. They cannot be fixed in app code
    // as they originate from the system's AppIntents framework initialization.
    @Environment(\.openWindow) private var openWindow
    
    private let commandRunner = CommandRunner()
    private let journal = TransactionJournal()
    private let cleanupViewModel: CleanupViewModel
    private let appSettings = AppSettings()
    private let permissionsManager = PermissionsManager()
    
    init() {
        let engine = CleanupEngine(commandRunner: commandRunner)
        self.cleanupViewModel = CleanupViewModel(engine: engine, journal: journal, settings: appSettings)

        // Request permissions at startup
        let manager = permissionsManager
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            manager.showGuidanceIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                cleanupViewModel: cleanupViewModel,
                journal: journal,
                appSettings: appSettings,
                permissionsManager: permissionsManager
            )
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacOS Cleaner") {
                    openWindow(id: "about")
                }
            }
        }
        
        Window("About MacOS Cleaner", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        Window("permissions_window_title".localized, id: "permissions") {
            PermissionsView(permissionsManager: permissionsManager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
