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

---

## Building a Distributable .app

To create a standalone `.app` bundle you can share with others (no Xcode required on their end):

### Option 1: Using Xcode (Recommended)

1. Open the project in Xcode:
   ```bash
   cd MacOSCleaner
   xcodegen
   open MacOSCleaner.xcodeproj
   ```

2. In Xcode:
   - Select **Product → Archive** (or `Cmd+Shift+Cmd+A`)
   - Wait for archiving to complete → **Distribute App** → **Copy App**
   - Choose a destination folder

3. The resulting `MacOSCleaner.app` is ready to share

### Option 2: Command Line (CI-friendly)

```bash
cd MacOSCleaner
xcodegen

# Build Release configuration
xcodebuild -project MacOSCleaner.xcodeproj \
  -scheme MacOSCleaner \
  -configuration Release \
  -derivedDataPath build \
  -archivePath build/MacOSCleaner.xcarchive \
  archive

# Export .app from archive
xcodebuild -exportArchive \
  -archivePath build/MacOSCleaner.xcarchive \
  -exportPath build/Export \
  -exportOptionsPlist ExportOptions.plist
```

Create `ExportOptions.plist` in the `MacOSCleaner` folder:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

The `.app` will be at `build/Export/MacOSCleaner.app`.

### Option 3: Quick Debug Build (for testing)

```bash
cd MacOSCleaner
xcodebuild -project MacOSCleaner.xcodeproj \
  -scheme MacOSCleaner \
  -configuration Debug \
  -derivedDataPath build
```

The app will be at `build/Build/Products/Debug/MacOSCleaner.app`.

---

### Code Signing for Distribution

**Without Apple Developer ID** (ad-hoc, for local testing only):
```bash
codesign --force --deep --sign - "/path/to/MacOSCleaner.app"
```
⚠️ Gatekeeper will block this on other Macs unless they right-click → Open.

**With Apple Developer ID** (recommended for sharing):
```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  "/path/to/MacOSCleaner.app"

# Notarize (required for macOS 10.15+)
xcrun notarytool submit "/path/to/MacOSCleaner.app" \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait

# Staple notarization ticket
xcrun stapler staple "/path/to/MacOSCleaner.app"
```

---

### Verify the Build

```bash
# Check code signature
codesign --verify --deep --strict --verbose=2 "/path/to/MacOSCleaner.app"

# Check notarization
spctl --assess --type execute --verbose "/path/to/MacOSCleaner.app"
```

---

**Logs:** open `Console.app` and filter by subsystem `com.alextkdev.macos-cleaner`.

---

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/AlexTkDev/MacOSCleaner/issues) — contributions are welcome.

---

## License

Custom Non-Commercial License — free to use, study, and fork for personal or educational purposes. Commercial use and redistribution are not permitted. See [LICENSE](LICENSE) for details.
