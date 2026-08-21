<h1 align="center">
  <img src=".github/logo.png?v=2" alt="MacOS Cleaner" width="100" align="absmiddle"> <br>
  <span>MacOS Cleaner</span>
</h1>

<p align="center">
  <strong>Fast, transparent, and 100% private macOS cleaner and app uninstaller.</strong><br>
  Built natively with Swift 6 and SwiftUI. Moves files to Trash by default — never silently destroys your data.
</p>

<p align="center">
  <a href="https://github.com/AlexTkDev/MacOSCleaner/releases/latest">
    <img src="https://img.shields.io/badge/Direct_Download-.dmg-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download DMG">
  </a>
  &nbsp;
  <a href="https://alextkdev.github.io/MacOSCleaner/">
    <img src="https://img.shields.io/badge/Official_Website-Visit_Site-238636?style=for-the-badge&logo=safari&logoColor=white" alt="Official Website">
  </a>
  &nbsp;
  <a href="https://github.com/AlexTkDev/MacOSCleaner/stargazers">
    <img src="https://img.shields.io/badge/Star_on_GitHub-⭐️-gold?style=for-the-badge&logo=github&logoColor=black" alt="Star on GitHub">
  </a>
</p>

<p align="center">
  <a href="https://github.com/AlexTkDev/MacOSCleaner/releases/tag/2.1.1"><img src="https://img.shields.io/badge/Release-v2.1.1-007AFF?style=flat&logo=apple&logoColor=white" alt="Release v2.1.1"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3%2BCommonsClause-blue.svg" alt="License"></a>
  <a href="https://github.com/AlexTkDev/MacOSCleaner/stargazers"><img src="https://img.shields.io/github/stars/AlexTkDev/MacOSCleaner?style=flat&logo=github&color=gold&cacheSeconds=3600" alt="Stars"></a>
  <a href="https://apple.com"><img src="https://img.shields.io/badge/Platform-macOS-000000.svg?logo=apple&logoColor=white" alt="Platform: macOS"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Language-Swift%206-FA7343?logo=swift&logoColor=white" alt="Swift 6"></a>
  <a href="https://developer.apple.com/documentation/swiftui/"><img src="https://img.shields.io/badge/UI-SwiftUI-007AFF?logo=swift&logoColor=white" alt="SwiftUI"></a>
  <a href="https://github.com/yonaskolb/XcodeGen"><img src="https://img.shields.io/badge/Build-XcodeGen-black.svg?logo=xcode&logoColor=white" alt="XcodeGen"></a>
  <a href="https://orcid.org/0009-0002-8907-5406"><img src="https://img.shields.io/badge/ORCID-0009--0002--8907--5406-A6CE39?logo=orcid&logoColor=white" alt="ORCID"></a>
</p>

---

## 🛡️ Trust & Safety by Design

System cleaning requires absolute trust. Unlike commercial or opaque utilities, **MacOS Cleaner** is built with five non-negotiable safety principles:

| Principle | Guarantee |
| :--- | :--- |
| 🚫 **Zero Telemetry** | **100% Offline.** No analytics, tracking, background daemons, or remote logging. |
| 🗑️ **Trash-First Safety** | Files are moved to macOS Trash (`trashItem(at:)`) — **never** permanently destroyed. Everything is recoverable. |
| 🔒 **Protected System Paths** | Fail-closed security. Hardcoded protection for SIP, `/System`, `/Library`, `/usr`, `~/.ssh`, and sensitive user data. |
| 📖 **100% Open Source** | Auditable Swift 6 codebase. Every rule, path, and file operation is open for public inspection. |
| ⚡ **100% Local Processing** | Traversal, hashes, and Apple Intelligence (`FoundationModels`) explanations run strictly on-device. |

---

## ✨ Key Advantages

- 🛠️ **Developer-Centric** — Deep cleanup for Xcode, Docker, Rust (`target`), Go (`pkg`), Node (`node_modules`), Python (`.venv`), Android Studio, and JetBrains.
- 🔬 **Forensic Uninstaller** — 30 evidence types, transparent *"Why this file?"* explanations, and rollback snapshots.
- ⚙️ **Process & Daemons Control** — Live CPU/RAM process monitor and safe LaunchAgents / LaunchDaemons manager.
- 🧠 **On-Device Apple Intelligence** — Native `FoundationModels` integration explains unknown files and caches completely offline.
- ⚡ **Pure Swift 6 & Native UI** — Low memory footprint, responsive Liquid Glass design, zero web/Electron runtime.
- 🆓 **100% Free & Open** — Fully featured, no paywalls, no subscriptions, no ads.

---

## 📸 Screenshots

<p align="center">
  <img src="assets/screenshots/Dashboard_v2_1.png" width="48%" alt="Dashboard">
  <img src="assets/screenshots/Uninstaller_v2_1.png" width="48%" alt="App Uninstaller">
</p>
<p align="center">
  <img src="assets/screenshots/Cleanup_Scan_v2_1.png" width="48%" alt="Smart Cleanup">
  <img src="assets/screenshots/Processes_v2_1.png" width="48%" alt="Process Manager">
</p>

<p align="center">
  <a href="assets/screenshots">📷 View all high-resolution screenshots</a>
</p>

---

## 🚀 Quick Download & Install

1. **Direct Download:** Grab the latest `.dmg` from [GitHub Releases](https://github.com/AlexTkDev/MacOSCleaner/releases/latest).
2. **Mount & Drag:** Open the `.dmg` and drag `MacOSCleaner.app` into `/Applications`.
3. **First Launch (Gatekeeper):** If macOS shows a Gatekeeper warning on locally built/unnotarized apps:
   ```bash
   sudo xattr -r -c /Applications/MacOSCleaner.app
   ```
   > *Note: This removes the quarantine attribute set by macOS. It does not modify app files, system security, or grant persistent permissions.*

---

## ✨ Core Features

### 🔍 Smart Cleanup
Scans 54 categories across 1,770 rule definitions for 251 apps and 66 developer toolchains using parallel actor-based disk traversal:
- **Caches & Containers** — Browsers (Safari, Chrome, Firefox, Arc), messengers, system/WebKit caches, and dynamic Electron discovery.
- **Developer Workspaces** — Xcode DerivedData & Simulators, Android SDK/Studio, JetBrains, VS Code, Cursor, Docker, and build artifacts (Rust `target`, Go `pkg`, Python `.venv`, Node `node_modules`, Flutter/Dart).
- **System Maintenance** — APFS purgeable space, Time Machine local snapshots, Mail downloads, crash reports, QuickLook thumbnails, and DNS cache flushing.
- **Leftovers & Junk** — Orphaned remnants, `.DS_Store`, `__MACOSX`, broken symlinks, old DMGs/PKGs, large archives, and unused apps.
- **Local AI Models** — Detects cache/model directories from Ollama, Hugging Face, LM Studio, Jan, MLX, PyTorch, and Whisper.

### 🗑️ App Uninstaller
Complete application removal with deep residual detection:
- **30 Evidence Types** — Correlates Bundle ID, Team ID, Spotlight metadata, Launch Services, and filesystem heuristics to find associated preferences, helpers, and caches.
- **Privileged Uninstallation** — Removes root-owned apps from `/Applications` with a single administrative authorization prompt.
- **Transparency ("Why this file?")** — Explains the exact forensic evidence behind every suggested residue file.
- **Rollback Snapshots** — Stores pre-removal states to verify complete uninstallation and assist recovery.

### 🧬 Duplicate File Finder
Fast, zero-dependency duplicate scanner using a 3-stage validation pipeline:
1. File size grouping
2. 4 KB header checksum
3. Full SHA-256 hash comparison with smart original selection

### 📁 Disk Space Analyzer
Visual directory explorer with breakdown by file types (Videos, Audio, Photos, Documents, Archives). Reveals items in Finder or moves them directly to Trash.

### ⚙️ Process Manager & Startup Services
- **Process Manager** — Live CPU, Memory, and Thread monitoring. One-click termination and force-quit with automatic protection for critical system daemons (`kernel_task`, `launchd`, `WindowServer`).
- **Startup Services** — Manages user and system LaunchAgents/LaunchDaemons with vendor filtering, permission escalation, and safety locks.

---

## 🍎 Native macOS Integrations

- **🧠 Apple Intelligence (macOS 26+)** — On-device explanations powered by `FoundationModels`. Operates completely offline to explain what specific caches, files, or processes do before you remove them.
- **🎙️ Siri & App Intents** — Native Shortcuts support. Automate cleanup routines, check available disk space, or clean developer caches via voice or scheduled workflows.
- **✨ Liquid Glass Interface** — Designed specifically for macOS 27 with native materials, activity rings, and full keyboard navigation (`⌘,`, `⌘C`, `⌘F`, `⌘R`).
- **🌍 10 Languages** — Fully localized (English, Deutsch, 日本語, Français, 简体中文, Italiano, Português-BR, Español, Русский, Українська).

---

## 🛠️ Tech Stack & Build from Source

- **Language:** Swift 6 (Strict concurrency, actors, structured `TaskGroup`)
- **UI:** SwiftUI (`@Observable`, `NavigationSplitView`, Charts, Liquid Glass)
- **Frameworks:** `AppIntents`, `FoundationModels`, `CryptoKit`, `OSLog`
- **Build System:** [XcodeGen](https://github.com/yonaskolb/XcodeGen)

**Build Prerequisites:** macOS 26.0+, Xcode 18+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# Clone repository
git clone https://github.com/AlexTkDev/MacOSCleaner.git
cd MacOSCleaner/MacOSCleaner

# Generate Xcode project & open
xcodegen
open MacOSCleaner.xcodeproj
```

*Press **⌘R** to build and run, or **⌘U** to execute tests.*

---

## ⭐️ Support & Discovery

Building a native, privacy-first cleaner takes continuous maintenance and testing. If MacOS Cleaner helped you reclaim disk space and keep your Mac fast:

<p align="center">
  <a href="https://github.com/AlexTkDev/MacOSCleaner/stargazers">
    <img src="https://img.shields.io/badge/⭐️_Star_MacOS_Cleaner_on_GitHub-Help_Others_Discover_Us-gold?style=for-the-badge&logo=github&logoColor=black" alt="Star MacOS Cleaner on GitHub">
  </a>
</p>

- 💬 **Discussions & Feature Requests:** [GitHub Discussions](https://github.com/AlexTkDev/MacOSCleaner/discussions)
- 🚧 **What's in development (2.2.0):** [MacOSCleaner 2.2.0 — in development](https://github.com/AlexTkDev/MacOSCleaner/discussions/14)
- 🐛 **Issue Tracker:** [GitHub Issues](https://github.com/AlexTkDev/MacOSCleaner/issues)
- 📖 **Documentation:** [MacOSCleaner Wiki](https://github.com/AlexTkDev/MacOSCleaner/wiki)

> *Note: Contributions are subject to the project's [Contributor License Agreement (CLA)](CLA.md).*

---

## 👨‍💻 Author

<table>
  <tr>
    <td width="72" align="center" valign="middle">
      <a href="https://github.com/AlexTkDev">
        <img src="https://github.com/AlexTkDev.png" width="64" height="64" style="border-radius: 50%;" alt="AlexTkDev">
      </a>
    </td>
    <td>
      <strong>Aleksandr (AlexTkDev)</strong><br>
      <a href="https://github.com/AlexTkDev"><img src="https://img.shields.io/badge/GitHub-AlexTkDev-181717?style=flat&logo=github" alt="GitHub"></a>
      <a href="https://orcid.org/0009-0002-8907-5406"><img src="https://img.shields.io/badge/ORCID-0009--0002--8907--5406-A6CE39?style=flat&logo=orcid&logoColor=white" alt="ORCID"></a>
      <a href="https://ko-fi.com/alextkdev"><img src="https://img.shields.io/badge/Ko--fi-Support-F16061?style=flat&logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
      <a href="DONATE.md"><img src="https://img.shields.io/badge/Donate-Crypto-F7931A?style=flat&logo=bitcoin&logoColor=white" alt="Donate"></a>
    </td>
  </tr>
</table>

> Academic or research reference: [`CITATION.cff`](CITATION.cff)

---

## License

Dual-licensed under:
- **[GNU GPLv3 + Commons Clause v1.0](LICENSE)** (Non-Commercial) for open-source use, personal study, and community distribution. Commercial resale or re-licensing is prohibited.
- **Commercial License** for enterprise or proprietary distribution. [Contact the author](https://github.com/AlexTkDev) for licensing inquiries.

> **Trademark Notice**: The license does not grant permission to use the project name ("MacOSCleaner"), logos, or branding in derivative works.

