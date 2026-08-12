# 🧹 macOS Cache Cleanup

[![License: Source-Available](https://img.shields.io/badge/License-Source--Available%20Personal%20Use-blue.svg)](LICENSE)
[![ORCID](https://img.shields.io/badge/ORCID-0009--0002--8907--5406-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0009-0002-8907-5406)

A high-performance shell script for safely cleaning up caches, temporary files, and application remnants on macOS. 
It uses an intelligent **whitelist and app-discovery approach**: only known-safe directories are targeted, and leftover files are detected based on the currently installed applications.

> **IMPORTANT:** This script is designed for safety. It **DOES NOT** touch system root directories (`/System`), critical SDK components, AVD images, user documents, or active application settings.

---

## 🚀 Launch Modes

Before the first run, make the script executable:
```bash
chmod +x macos-cache-cleanup.sh
```

**Standard cleanup:**
```bash
./macos-cache-cleanup.sh
```

**Dry Run Mode — preview only, nothing is deleted:**
```bash
./macos-cache-cleanup.sh --dry-run
```

**Scan Mode — deep discovery report (includes orphaned app remnants and large files):**
```bash
./macos-cache-cleanup.sh --scan
```

**Cleanup with additional flags:**
```bash
# Clean module caches (Go, Maven) and deep-clean project artifacts (.dart_tool)
./macos-cache-cleanup.sh --clean-modcache --clean-maven --clean-projects

# Clean .DS_Store and scattered junk (Finder metadata)
./macos-cache-cleanup.sh --clean-ds-store
```

---

## 📋 What the script cleans (20 steps)

The script performs a comprehensive 20-step cleanup:

1. **User app caches (whitelist)**: Google, CocoaPods, Homebrew, Playwright, Spotify, Xcode, SwiftPM, JetBrains, etc.
2. **Package managers (native)**: `brew`, `npm`, `yarn`, `pnpm`, `pod` native cleanup commands.
3. **Gradle + Maven caches**: Gradle daemons/wrappers and optional Maven repo cleanup.
4. **Flutter / Dart / pub-cache**: Package caches and optional project `.dart_tool` removal.
5. **Xcode (Build Data)**: DerivedData, DeviceSupport, and archives older than 90 days.
6. **iOS Simulators**: Caches, unavailable devices, and old iOS runtimes (keeps the latest stable version).
7. **Android SDK**: Build caches and intelligent removal of old `build-tools` and `platforms`.
8. **IDE & AI Caches**: Caches for Cursor, VS Code, JetBrains, Claude, ChatGPT, etc. (settings preserved).
9. **Browser caches**: Safari, Chrome, Firefox, Edge, Brave, Opera.
10. **Media & Messaging**: Telegram, Slack, Discord, Spotify, Zoom, iMessage attachments.
11. **Docker cleanup**: `system prune` and `builder prune` (if Docker is running).
12. **Language & Runtimes**: Go, Rust, Node (Bun, Deno), Python, Ruby, PHP, JVM, etc.
13. **Logs & Diagnostics**: User logs (>7 days) and macOS crash reports.
14. **System Caches (User-space)**: QuickLook, fontd, helpd, iconservices.
15. **App Container Caches**: Caches inside `~/Library/Containers` and `~/Library/Group Containers`.
16. **AI CLI Tools**: Caches for opencode, Claude CLI, Ollama logs, etc.
17. **Scattered Junk Files**: `.DS_Store`, `__MACOSX`, and stray log files (Optional: `--clean-ds-store`).
18. **Dynamic Cache Discovery**: Intelligent scan of `~/Library/Caches` for unknown safe entries > 50 MB.
19. **Orphaned App Remnants**: **Deep scan** for leftover files from uninstalled apps in `Application Support`, `Containers`, `Group Containers`, `Cookies`, `Preferences`, and `/Users/Shared`.
20. **System & Large Files Scanner**: Detects old iOS updates (`.ipsw`), external drive trashes, huge Mail storage, and large installers (>100 MB).

---

## 🛡 Safety Features

* **App-Aware Logic**: Detects currently installed apps to avoid deleting data for programs you still use.
* **Intelligent Whitelisting**: Specifically ignores high-value data like LLM models (Ollama, HuggingFace).
* **Auto-Close**: Gracefully closes IDEs and browsers before cleanup to prevent database corruption.
* **Non-Destructive**: For system directories, it only cleans contents or reports size without deletion.
* **No `sudo` Required**: Operates safely within user-space permissions.

---

## 🛠 Advanced Customization

The script is built with modular helper functions:
- `clean_contents`: Safely empties a directory while preserving the folder itself.
- `_is_installed`: Cross-references folder names with the list of installed applications.
- `print_step`: Displays a beautiful progress bar and formatted status for each stage.

---

## Author

**AlexTkDev** — [ORCID 0009-0002-8907-5406](https://orcid.org/0009-0002-8907-5406)

Machine-readable citation: [`CITATION.cff`](CITATION.cff)

## License

**[SOURCE-AVAILABLE PERSONAL USE ONLY](LICENSE)** — personal / non-commercial study only.
Commercial use, redistribution for sale, and re-licensing require prior written permission from the author.
