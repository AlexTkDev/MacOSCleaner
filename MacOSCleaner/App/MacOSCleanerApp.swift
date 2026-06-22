import SwiftUI
import OSLog

private let crashLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner", category: "Crash")

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
        Self.installCrashHandlers()
        
        let engine = CleanupEngine(commandRunner: commandRunner)
        self.cleanupViewModel = CleanupViewModel(engine: engine, journal: journal, settings: appSettings)

        // Request permissions at startup
        let manager = permissionsManager
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            manager.showGuidanceIfNeeded()
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
