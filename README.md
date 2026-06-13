# macOS Cleaner

[![License: Custom Non-Commercial](https://img.shields.io/badge/License-Custom%20NC-orange.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-000000.svg?logo=apple&logoColor=white)](https://apple.com)
[![Language: Swift 6](https://img.shields.io/badge/Language-Swift%206-FA7343.svg?logo=swift&logoColor=white)](https://swift.org)
[![UI: SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF.svg?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Build: XcodeGen](https://img.shields.io/badge/Build-XcodeGen-black.svg?logo=xcode&logoColor=white)](https://github.com/yonaskolb/XcodeGen)

Native macOS app built with Swift 6 & SwiftUI to reclaim disk space and keep your Mac tidy. Nothing is permanently deleted — everything goes to Trash, so you can always restore it.

---

## Features

**Dashboard** — disk usage chart, system info (model, CPU, RAM, OS version), cleanup history and statistics.

**Smart Cleanup** — comprehensive system cleanup with 22 categories:

- **User Caches** — app caches, browser caches (Safari, Chrome, Firefox, Edge, Brave, Vivaldi, Arc), messaging caches (Telegram, Discord, Slack, Signal, WeChat, Teams)
- **Package Managers** — Homebrew, npm, yarn, pnpm, CocoaPods cache cleanup
- **Development Tools** — Xcode DerivedData, iOS Simulators, Android SDK/caches, Gradle/Maven/Gradle, Flutter/Dart, language caches (Go, Rust, Python, Node.js, Ruby, Java, Julia, Elixir, Haskell, Swift PM)
- **IDE Caches** — Cursor, VS Code, Windsurf, Zed, JetBrains, Sublime Text, Claude, ChatGPT, Slack, Discord, Figma, Notion, Postman, Linear
- **System Caches** — QuickLook, fonts, Spotlight, Siri, CloudKit, TimeMachine, diagnosticd
- **Docker** — container and image cleanup
- **App Containers** — sandboxed app caches (Containers + Group Containers)
- **Dotfile Caches** — AI CLI tools (opencode, Claude, Gemini, Codex, Aider), dev tool caches (npm logs, Terraform, Helm, Bazel, ccache, vcpkg)
- **Scattered Junk** — recursive .DS_Store removal, __MACOSX directories
- **Orphaned Files** — HTTPStorages, WebKit entries for uninstalled apps
- **Large Files** — old DMG/pkg/iso/zip installers, node_modules, iPhone backups, IPSW firmware, Mail Downloads
- **Dynamic Cache Discovery** — auto-discovers large reverse-DNS cache directories in ~/Library/Caches

All categories are always scanned. Dev-related categories display a purple "DEV" badge in the UI. You pick what to delete, then confirm.

**Process Manager** — lists running processes, lets you terminate or force-kill them with built-in safety (protected system processes cannot be killed).

**Startup Services** — lists all LaunchAgents from `~/Library/LaunchAgents`, shows their load status, and lets you enable or disable them without touching system agents.

**App Uninstaller** — finds installed apps, scans for residual files across known support directories (Caches, Preferences, Application Support, Logs), shows total space to reclaim. Expert Mode lets you cherry-pick which leftovers to remove.

**Settings** — light/dark/system theme, language switcher (English, Русский, Українська), notification toggles, scan-on-startup, Trash behavior, and more.

**Multilingual UI** — runtime language switching without restart, using a custom `LanguageManager` backed by `Localizable.strings` for `en`, `ru`, `uk`.

---

## Safety

- All deletions go through `trashItem(at:)` — recoverable from Trash by default.
- `SafetyManager` blocks writes to `/System`, `/usr`, `/bin`, `~/.ssh`, and other critical paths.
- `ProcessSafetyPolicy` protects critical system processes (kernel_task, launchd, WindowServer) from termination.
- Permanent deletion (bypassing Trash) is opt-in and clearly marked in the UI.
- Apps are closed before cleanup starts (graceful terminate, then force-kill after 3s timeout).
- Full Disk Access permission is requested at startup.

---

## Tech Stack

- **Swift 6** — strict concurrency, actors, `async/await`, structured task groups
- **SwiftUI** — declarative UI, `@Observable`, `NavigationSplitView`, Charts
- **Architecture** — feature-oriented folders, component-based cleanup (Coordinator, Engine, ItemManager, Notifier), no third-party UI frameworks
- **CleanupEngine** — hybrid actor using FileManager for safe file ops and Process for system commands (brew, npm, docker), with configurable timeouts and cancellation
- **Build** — XcodeGen (`project.yml` as single source of truth)
- **Logging** — OSLog with structured subsystems

---

## Project Structure

```
MacOSCleaner/
├── App/          # Entry point, RootView, sidebar navigation
├── Domains/
│   ├── Cleanup/  # CleanupStateMachine, CleanupCoordinator, CleanupEngine,
│   │             # CleanupItemManager, CleanupNotifier, CleanupModels, TransactionJournal
│   ├── ProcessManagement/  # ProcessManager, ProcessSafetyPolicy
│   └── StartupServices/    # LaunchServiceManager
├── Features/     # SwiftUI views + ViewModels (Dashboard, Cleanup, Processes, Settings, About)
├── Infrastructure/  # System services (CommandRunner, SafetyManager, TrashManager, LanguageManager)
├── Models/       # Shared value types and enums (CleanupItem, OperationRisk, RunningProcess, etc.)
└── Resources/    # Localizable.strings (en/ru/uk), assets
```

---

## Quick Start

**Requirements:** Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
cd MacOSCleaner
xcodegen
open MacOSCleaner.xcodeproj
# Cmd+R to run, Cmd+U to run tests
```

**Ad-hoc signing** (for local use without a developer account):
```bash
codesign --force --deep --sign - "/Applications/MacOSCleaner.app"
```

**Logs:** open `Console.app` and filter by subsystem `com.alextkdev.macos-cleaner`.

---

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/AlexTkDev/MacOSCleaner/issues) — contributions are welcome.

---

## License

Custom Non-Commercial License — free to use, study, and fork for personal or educational purposes. Commercial use and redistribution are not permitted. See [LICENSE](LICENSE) for details.
