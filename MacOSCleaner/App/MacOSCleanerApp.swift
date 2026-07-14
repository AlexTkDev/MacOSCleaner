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
    @State private var availableUpdate: String? = nil
    
    init() {
        Self.installCrashHandlers()
        
        let engine = CleanupEngine(commandRunner: commandRunner)
        self.cleanupViewModel = CleanupViewModel(engine: engine, journal: journal, settings: appSettings)

        // Preload Launch Services cache
        Task { await LSRegisterCache().warmup() }
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
        WindowGroup {
            RootView(
                cleanupViewModel: cleanupViewModel,
                journal: journal,
                appSettings: appSettings,
                permissionsManager: permissionsManager,
                availableUpdate: $availableUpdate
            )
            .task {
                availableUpdate = await updateChecker.checkForUpdate()
            }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("about_title".localized) {
                    openWindow(id: "about")
                }
            }
        }
        
        Window("about_title".localized, id: "about") {
            AboutView(availableUpdate: availableUpdate)
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
