<p align="center">
  <img src=".github/logo.png" alt="macOS Cleaner" width="128">
</p>

<h1 align="center">macOS Cleaner</h1>

[![License: Custom Non-Commercial](https://img.shields.io/badge/License-Custom%20NC-orange.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-000000.svg?logo=apple&logoColor=white)](https://apple.com)
[![Language: Swift 6](https://img.shields.io/badge/Language-Swift%206-FA7343.svg?logo=swift&logoColor=white)](https://swift.org)
[![UI: SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF.svg?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Build: XcodeGen](https://img.shields.io/badge/Build-XcodeGen-black.svg?logo=xcode&logoColor=white)](https://github.com/yonaskolb/XcodeGen)
[![Version: 1.1.1](https://img.shields.io/badge/Release-1.1.1-brightgreen.svg)]()

🧹 Free up disk space by cleaning caches, temp files, app leftovers, and more. Everything goes to Trash — nothing is gone forever unless you say so.

---

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/AlexTkDev/MacOSCleaner/dev/release-1.1.1/assets/screenshots/Dashboard.png" width="45%">
  <img src="https://raw.githubusercontent.com/AlexTkDev/MacOSCleaner/dev/release-1.1.1/assets/screenshots/Uninstaller.png" width="45%">
</p>
<p align="center">
  <img src="https://raw.githubusercontent.com/AlexTkDev/MacOSCleaner/dev/release-1.1.1/assets/screenshots/Cleanup_Scan.png" width="45%">
  <img src="https://raw.githubusercontent.com/AlexTkDev/MacOSCleaner/dev/release-1.1.1/assets/screenshots/Processes.png" width="45%">
</p>

<p align="center">
  <a href="https://github.com/AlexTkDev/MacOSCleaner/tree/dev/release-1.1.1/assets/screenshots">📷 View all screenshots</a>
</p>

---

## Features

🌍 **Fully Localized** — English, Русский, Українська, Español. All UI, errors, logs, and system info translated dynamically. Dates and byte counts format automatically for your language.

**Dashboard** 📊 — redesigned with native macOS aesthetics: `controlBackgroundColor`, rounded cards, and SF Symbols. Disk usage chart, system info (model, CPU, RAM, macOS version), cleanup history and stats.

**Smart Cleanup** 🔍 — scans 54 categories with 298 built-in cleaning paths:

- **App Caches** — Google, Spotify, JetBrains, opencode, browsers (Safari, Chrome, Firefox, Edge, Brave, Vivaldi, Arc), messengers (Telegram, Discord, Slack, Signal, WeChat, Teams)
- **Package Managers** — Homebrew, npm, yarn, pnpm, CocoaPods
- **Dev Tools** — Xcode DerivedData, iOS Simulators (old runtimes too), Android SDK + Studio caches, Gradle/Maven, Flutter/Dart, language caches (Go, Rust, Python, Node.js, Ruby, Java, Julia, Elixir, Haskell, Swift PM, R, Maven, pnpm-store, Yarn, Poetry, Cargo git, SwiftPM repos, Bazel)
- **IDE Caches** — Cursor, VS Code (incl. Insiders), Windsurf, Zed, JetBrains, Nova, Sublime Text, Atom, Eclipse, opencode, Claude, ChatGPT, Gemini, Perplexity, GitHub Desktop, Slack, Discord, Figma, Notion, Postman, Insomnia, Linear, Tower, TablePlus + dynamic Electron cache discovery
- **Browser Sub-Caches** — Firefox Profiles/*/cache2, Safari LocalStorage/Databases, Chrome Code Cache/GPUCache/Service Worker/GrShaderCache, Edge/Brave/Arc Code Cache
- **System Caches** — QuickLook ThumbnailsAgent, fonts, Spotlight, Siri, CloudKit, TimeMachine, icons
- **Docker** — container and image cleanup
- **App Containers** — sandboxed caches in Containers + Group Containers
- **Dotfile Caches** — AI CLI tools (opencode, Claude, Gemini, Codex, Aider), dev tools (npm logs, Terraform, Helm, Bazel, ccache, vcpkg)
- **Scattered Junk** — .DS_Store, __MACOSX, stray logs, Windows metadata (Thumbs.db, desktop.ini), broken symlinks
- **Orphaned Files** — leftovers from uninstalled apps in HTTPStorages, WebKit, Cookies, /Users/Shared
- **Old IDE Versions** — cleans system caches for VS Code, Cursor, Windsurf, Zed, Sublime Text, Eclipse, Atom; detects and removes leftover JetBrains cache/log directories for no-longer-installed products; cleans old Android Studio version caches (keeps latest); removes stale CachedData subdirectories for VS Code, Cursor, Windsurf (keeps latest version)
- **Large Files** — old DMG/pkg/iso/zip installers, node_modules (recursive), iPhone backups, IPSW firmware
- **Dynamic Cache Discovery** — auto-discovers large reverse-DNS caches in ~/Library/Caches; Apple caches (com.apple.*) at ≥ 5 MB, others at ≥ 20 MB
- **Time Machine Snapshots** — local APFS snapshots (macOS recreates them automatically)
- **iOS Backups** — re-downloadable from iCloud
- **Mail Downloads** — cached email attachments (all Mail accounts)
- **Saved Application State** — window/session state (recreated on app launch)
- **Crash Reports** — old crash logs and diagnostic files
- **AssetsV2 / iWork Templates** — Pages/Numbers/Keynote templates (~800 MB, re-downloaded on demand)
- **iCloud CloudKit Cache** — metadata cache (rebuilt automatically)
- **SwiftPM Cache** — build/download cache (rebuilt on next build)
- **Carthage Cache** — dependency cache and spec repos
- **Steam Cache** — app cache, shader cache, depot cache, logs
- **Teams Cache** — Electron caches (Cache, Code Cache, GPUCache, IndexedDB)
- **Adobe Caches** — application and media caches
- **Chrome Extra Caches** — GrShaderCache, disk cache, code cache, GPU cache, service workers
- **Launch Agents** — user-level LaunchAgents in ~/Library/LaunchAgents
- **Launch Daemons** — system-level LaunchDaemons (sudo)
- **Privileged Helpers** — system helper tools (sudo)
- **Package Receipts** — pkgutil receipt databases
- **Internet Plug-Ins** — legacy browser plug-ins
- **Shared File Lists** — Finder sidebar / recent items lists
- **iCloud Cloud Documents** — iCloud document cache (opt-in)
- **Photos Library Cache** — Photos.app library cache
- **Voice Memos** — Voice Memos recordings (opt-in)
- **GarageBand / Logic** — project files and caches (opt-in)
- **iMovie / Final Cut** — render files and libraries (opt-in)
- **Garmin / Fitbit** — device sync caches
- **Old Backups** — stale .backup files in Home, Desktop, Documents, Downloads
- **DNS Cache Flush** — flushes DNS resolver cache (command, sudo)
- **Font Cache** — rebuilds font databases (command, sudo)
- **Sleep Image** — removes /var/vm/sleepimage (command, sudo, opt-in)
- **Duplicate Files** — sha256 duplicate detection in ~/Documents, ~/Desktop, ~/Downloads, ~/Pictures, ~/Movies
- **Unused Apps** — apps not launched in 180+ days (scan-only)

Cleanup tasks run in parallel across all available cores for maximum speed. All categories are always scanned. Dev-related ones show a purple "DEV" badge. Risk badges (Safe / Moderate / Dangerous / Protected) appear after scan — you pick what to delete, then confirm.

**Cleanup Options** — toggles before scan:
- **Clean .DS_Store files** — removes Finder metadata from directories (off by default)
- **Clean iCloud Documents** — includes iCloud document cache (off by default)
- **Clean Voice Memos** — includes Voice Memos recordings (off by default)
- **Clean GarageBand / Logic** — includes project files and caches (off by default)
- **Clean iMovie / Final Cut** — includes render files and libraries (off by default)
- **Clean Sleep Image** — removes hibernation image file (off by default)

**Process Manager** ⚙️ — redesigned with modern macOS styling. Lists running processes, lets you terminate or force-kill them. Critical system processes (kernel_task, launchd, WindowServer) are protected.

**Startup Services** 🚀 — redesigned with modern macOS styling. Shows all LaunchAgents from `~/Library/LaunchAgents`, their load status, and lets you enable/disable them.

**App Uninstaller** 🗑️ — finds installed apps, scans 5 levels deep for residual files using 14 types of evidence (Bundle ID, Team ID, Spotlight, Plist contents, and more). Shows total reclaimable space and real-time scan progress. Tailored rules for over 95 popular apps including Docker, Parallels, Adobe CC, MS Office, Discord, Figma, and more.

- **Scan Modes (Safe / Balanced)** — choose between *Safe* mode (exact matches only, no Spotlight, highest confidence files) and *Balanced* mode (full deep scan including Spotlight and fuzzy matching) to tailor uninstallation aggressiveness
- **Background Deep Scanning** — apps are scanned thoroughly in the background; the UI updates in real time as each app's total size is finalized
- **Evidence-Based Forensics** — each candidate file is scored against 14 evidence types: identity, code signing, system integration, metadata, content analysis, graph relationships, and Launch Services registration
- **Confidence Tiers** — `.guaranteed` (critical evidence), `.veryLikely`, `.possible`, or `.ignore`
- **Developer Components** — detects and offers to clean Android SDK, Gradle/Maven, Xcode DerivedData, iOS Simulators, Flutter pub-cache, Docker containers, and Homebrew artifacts
- **Reveal in Finder** — quick action to show any related file or folder in Finder before deleting
- **Why this file?** — each related file includes an evidence breakdown with localized explanations. Tap any file to see exactly why it was associated with the app
- **Post-Uninstall Verification** — re-scan confirms cleanup completeness; snapshots stored for rollback

**Smart Updates** 🔄 — automatic, lightweight background check for new versions on startup directly via GitHub Releases. Get gently notified when a new update is ready, without background daemons, persistent tracking, or extra dependencies.

**Settings** — rebuilt with native macOS `Form` styles to match System Settings. Light/dark/system theme, languages (English, Русский, Українська, Español), notifications, scan-on-startup, Trash behavior, and more.

---

## How It Works

Runs on Apple Silicon (M1–M5) with full parallelism — cleanup categories execute concurrently across all available cores. File scanning is done with a stack-based iterator that batches work and deduplicates inodes. Size calculations are cached to avoid redundant work. All cleanup paths are embedded as static Swift arrays — no runtime JSON parsing.

---

## Safety 🛡️

- Everything goes to Trash via `trashItem(at:)` — always recoverable
- `SafetyManager` blocks access to `/System`, `/usr`, `/bin`, `~/.ssh`, and other critical paths
- `ProcessSafetyPolicy` protects system-critical processes from termination
- Permanent deletion is opt-in and clearly marked in the UI
- Apps are closed before cleanup (graceful terminate → force-kill after 3s)
- Full Disk Access is requested at startup

---

## Tech Stack

- **Swift 6** — actors, `async/await`, structured task groups
- **SwiftUI** — `@Observable`, `NavigationSplitView`, Charts
- **Build** — XcodeGen, whole-module optimization, `-O` Swift flag
- **Logging** — OSLog with structured subsystems
- **Architecture** — feature-oriented folders, component-based cleanup

---

## Project Structure

```
MacOSCleaner/
├ App/                    # Entry point, RootView, sidebar navigation
├ Domains/
│  ├ Cleanup/             # Coordinator, Engine, StateMachine, ItemManager, Notifier, Models, EmbeddedCleanupPaths
│  ├ ProcessManagement/   # ProcessManager, ProcessSafetyPolicy
│  └ StartupServices/     # LaunchServiceManager
├ Features/
│  ├ Dashboard/           # DashboardView + ViewModel
│  ├ Cleanup/             # CleanupView + ViewModel, AnimatedScanView
│  ├ Processes/           # ProcessesView + ViewModel, ProcessRow
│  ├ Settings/            # SettingsView, AppSettings, StartupVendorSettings
│  ├ Uninstaller/         # 30 application rules, forensics engine, caches, UI
│  ├ StartupServices/     # StartupServicesView + ViewModel
│  ├ Permissions/         # PermissionsView
│  └ About/               # AboutView
├ Infrastructure/         # CommandRunner, SafetyManager, TrashManager, LanguageManager, PosixScanner, actors
├ Models/                 # CleanupItem, OperationRisk, RunningProcess, StartupService, etc.
└ Resources/              # Localizable.strings (en/ru/uk/es), assets
```

---

## Quick Start

**Requirements:** macOS 15.5+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
cd MacOSCleaner
xcodegen
open MacOSCleaner.xcodeproj
# Cmd+R to run, Cmd+U to run tests
```

---

## Building a Distributable .app

### Option 1: Xcode (Recommended)

```bash
cd MacOSCleaner
xcodegen
open MacOSCleaner.xcodeproj
```

In Xcode: **Product → Archive** → **Distribute App** → **Copy App** → choose destination.

### Option 2: Command Line

```bash
cd MacOSCleaner
xcodegen

xcodebuild -project MacOSCleaner.xcodeproj \
  -scheme MacOSCleaner \
  -configuration Release \
  -derivedDataPath build \
  -archivePath build/MacOSCleaner.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/MacOSCleaner.xcarchive \
  -exportPath build/Export \
  -exportOptionsPlist ExportOptions.plist
```

Create `ExportOptions.plist`:

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

### Option 3: Debug Build

```bash
cd MacOSCleaner
xcodebuild -project MacOSCleaner.xcodeproj \
  -scheme MacOSCleaner \
  -configuration Debug \
  -derivedDataPath build
```

---

## Code Signing

**Ad-hoc** (local testing only):
```bash
codesign --force --deep --sign - "/path/to/MacOSCleaner.app"
```
Gatekeeper will block this on other Macs unless they right-click → Open.

**Developer ID** (recommended for sharing):
```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  "/path/to/MacOSCleaner.app"

xcrun notarytool submit "/path/to/MacOSCleaner.app" \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait

xcrun stapler staple "/path/to/MacOSCleaner.app"
```

**Verify:**
```bash
codesign --verify --deep --strict --verbose=2 "/path/to/MacOSCleaner.app"
spctl --assess --type execute --verbose "/path/to/MacOSCleaner.app"
```

**Fix damaged app attributes:**
```bash
sudo xattr -r -c /path/to/MacOSCleaner.app
```

---

**Logs:** open `Console.app` → filter by subsystem `com.alextkdev.macos-cleaner`.

---

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/AlexTkDev/MacOSCleaner/issues) — contributions are welcome.

---

## License

Custom Non-Commercial License — free to use, study, and fork for personal or educational purposes. Commercial use and redistribution are not permitted. See [LICENSE](LICENSE) for details.
