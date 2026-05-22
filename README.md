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

**Smart Cleanup** — scans and removes user caches, app logs, Xcode DerivedData, Android Studio caches, Go/Maven build artifacts, Homebrew cache, and `.DS_Store` files. You pick what to delete, then confirm.

**Startup Services** — lists all LaunchAgents from `~/Library/LaunchAgents`, shows their load status, and lets you enable or disable them without touching system agents.

**App Uninstaller** — finds installed apps, scans for residual files across known support directories (Caches, Preferences, Application Support, Logs), shows total space to reclaim. Expert Mode lets you cherry-pick which leftovers to remove.

**Settings** — light/dark/system theme, language switcher (English, Русский, Українська), notification toggles, scan-on-startup, Trash behavior, and more.

**Multilingual UI** — runtime language switching without restart, using a custom `LanguageManager` backed by `Localizable.strings` for `en`, `ru`, `uk`.

---

## Safety

- All deletions go through `trashItem(at:)` — recoverable from Trash by default.
- `SafetyManager` blocks writes to `/System`, `/usr`, `/bin`, `~/.ssh`, and other critical paths.
- Permanent deletion (bypassing Trash) is opt-in and clearly marked in the UI.

---

## Tech Stack

- **Swift 6** — strict concurrency, actors, `async/await`, structured task groups
- **SwiftUI** — declarative UI, `@Observable`, `NavigationSplitView`, Charts
- **Architecture** — pragmatic MVP, feature-oriented folders, no third-party UI frameworks
- **Build** — XcodeGen (`project.yml` as single source of truth)
- **Logging** — OSLog with structured subsystems

---

## Project Structure

```
MacOSCleaner/
├── App/          # Entry point, RootView, sidebar navigation
├── Domains/      # Business logic (CleanupStateMachine, LaunchServiceManager, UninstallerService)
├── Features/     # SwiftUI views + ViewModels (Dashboard, Cleanup, Uninstaller, Settings, About)
├── Infrastructure/  # System services (CommandRunner, SafetyManager, TrashManager, LanguageManager)
├── Models/       # Shared value types and enums
└── Resources/    # Localizable.strings (en/ru/uk), shell scripts, assets
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