import SwiftUI

@main
struct MacOSCleanerApp: App {
    @Environment(\.openWindow) private var openWindow
    
    private let commandRunner = CommandRunner()
    private let journal = TransactionJournal()
    private let cleanupViewModel: CleanupViewModel
    private let appSettings = AppSettings()
    
    init() {
        let adapter = ShellCleanupAdapter(commandRunner: commandRunner)
        self.cleanupViewModel = CleanupViewModel(adapter: adapter, journal: journal, settings: appSettings)
    }

    var body: some Scene {
        WindowGroup {
            RootView(cleanupViewModel: cleanupViewModel, journal: journal, appSettings: appSettings)
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
    }
}