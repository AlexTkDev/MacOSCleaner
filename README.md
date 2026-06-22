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

**Smart Cleanup** — comprehensive system cleanup with 35 categories:

- **User Caches** — app caches (Google, Spotify, JetBrains, opencode), browser caches (Safari, Chrome, Firefox, Edge, Brave, Vivaldi, Arc), messaging caches (Telegram, Discord, Slack, Signal, WeChat, Teams, Spotify)
- **Package Managers** — Homebrew, npm (with manual fallback), yarn, pnpm, CocoaPods cache cleanup
- **Development Tools** — Xcode DerivedData, iOS Simulators (including old runtime cleanup), Android SDK/caches + Android Studio cache discovery, Gradle/Maven, Flutter/Dart (.pub-cache, .flutter-devtools, .dart_tool project scanning), language caches (Go, Rust, Python, Node.js, Ruby, Java, Julia, Elixir, Haskell, Swift PM, R)
- **IDE Caches** — Cursor, VS Code, Windsurf, Zed, JetBrains, Nova, Sublime Text/Merge, Atom, Claude, ChatGPT, Gemini, Perplexity, Slack, Discord, Figma, Notion, Postman, Insomnia, Linear, GitHub Desktop, 1Password, Tower, TablePlus, opencode + dynamic Electron cache discovery
- **System Caches** — QuickLook, fonts, Spotlight, Siri, CloudKit, TimeMachine, diagnosticd, parsecd, icons
- **Docker** — container and image cleanup
- **App Containers** — sandboxed app caches (Containers + Group Containers)
- **Dotfile Caches** — AI CLI tools (opencode, Claude, Gemini, Codex, Aider), dev tool caches (npm logs, Terraform, Helm, Bazel, ccache, vcpkg)
- **Scattered Junk** — recursive .DS_Store removal (including project dirs), __MACOSX directories, stray log files, Windows metadata (Thumbs.db, desktop.ini), broken symlinks
- **Orphaned Files** — HTTPStorages, WebKit, Cookies, /Users/Shared entries for uninstalled apps
- **Large Files** — old DMG/pkg/iso/zip installers (Downloads, Desktop, Documents), node_modules (recursive), iPhone backups, IPSW firmware
- **Dynamic Cache Discovery** — auto-discovers large reverse-DNS cache directories in ~/Library/Caches; Apple caches (com.apple.*) auto-cleaned at ≥ 5 MB, others at ≥ 50 MB
- **Time Machine Snapshots** — local APFS snapshots (safe to delete, macOS recreates)
- **iOS Backups** — iPhone/iPad backups from Finder/iTunes (re-downloadable from iCloud)
- **Mail Downloads** — cached email attachments
- **Saved Application State** — window/session state for app resume (recreated on launch)
- **Crash Reporter** — old crash reports and diagnostic logs
- **AssetsV2 / iWork Templates** — Pages/Numbers/Keynote templates (~800 MB, re-downloaded on demand)
- **iCloud CloudKit Cache** — iCloud metadata cache (rebuilt automatically)
- **Swift Package Manager Cache** — build/download cache (rebuilt on next build)
- **Carthage Cache** — dependency cache and spec repos (re-downloaded on next build)
- **Steam Cache** — app cache, shader cache, depot cache, logs
- **Microsoft Teams Cache** — Electron caches (Cache, Code Cache, GPUCache, IndexedDB)
- **Adobe Caches** — application caches and media cache
- **Chrome Extra Caches** — disk cache, code cache, GPU cache, service workers

All categories are always scanned. Dev-related categories display a purple "DEV" badge in the UI. Risk badges (Safe/Moderate/Dangerous) shown after scan. You pick what to delete, then confirm.

**Cleanup Options** — additional opt-in options in the UI:
- **Clean .DS_Store files** — removes Finder metadata from directories (off by default, also available as "Scattered Junk" category)
- **Clean Maven repository** — removes ~/.m2/repository (on by default, re-downloads on next build)
- **Clean Go module cache** — removes GOMODCACHE (on by default, re-downloads on next build)
- **Clean .dart_tool in projects** — scans ~/Documents, ~/Projects, ~/Developer, ~/dev, ~/code, ~/repos (on by default)

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
