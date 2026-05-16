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

    var body: some Scene {
        WindowGroup {
            RootView()
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