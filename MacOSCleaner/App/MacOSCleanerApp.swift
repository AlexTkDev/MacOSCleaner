//
//  MacOSCleanerApp.swift
//  MacOSCleaner
//
//  Created by Alex on 14.05.2026.
//

import SwiftUI

@main
struct MacOSCleanerApp: App {
    @Environment(\.openWindow) private var openWindow
    
    private let commandRunner = CommandRunner()
    private let journal = TransactionJournal()
    private let cleanupViewModel: CleanupViewModel
    
    init() {
        let adapter = ShellCleanupAdapter(commandRunner: commandRunner)
        self.cleanupViewModel = CleanupViewModel(adapter: adapter, journal: journal)
    }

    var body: some Scene {
        WindowGroup {
            RootView(cleanupViewModel: cleanupViewModel)
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