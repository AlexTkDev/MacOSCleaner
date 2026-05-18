# 🧼 macOS Cleaner GUI

[![License: Custom Non-Commercial](https://img.shields.io/badge/License-Custom%20NC-orange.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-000000.svg?logo=apple&logoColor=white)](https://apple.com)
[![Language: Swift 6](https://img.shields.io/badge/Language-Swift%206-FA7343.svg?logo=swift&logoColor=white)](https://swift.org)
[![UI: SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF.svg?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Build: XcodeGen](https://img.shields.io/badge/Build-XcodeGen-black.svg?logo=xcode&logoColor=white)](https://github.com/yonaskolb/XcodeGen)

A gorgeous, lightweight, and super fast native macOS app 🚀 built with **Swift 6 & SwiftUI** to keep your Mac clean and running like new! 🌟 Zero permanent deletions by default — we move everything safely to the Trash! 🛡️

---

## ✨ Features at a Glance

- 📊 **Dashboard:** Real-time disk charts, system specs (Mac Model, RAM, CPU), and history.
- 🧹 **Smart Cleanup:** Safely purges logs, user/app caches, Xcode DerivedData, Android Studio, and Homebrew caches.
- 🚀 **Startup Services:** Scan and manage LaunchAgents (`~/Library/LaunchAgents`) to boost boot times.
- 📦 **App Uninstaller:** Multi-pass deep scanning for application leftovers with an **Expert Mode** and size statistics.
- 🧳 **Safety First:** Driven by `SafetyManager` to block accidental modifications of critical directories (`/System`, `~/.ssh`). Uses `trashItem(at:)` for easy restore. 🔄

---

## 🏗️ Tech Stack & Structure

```text
- Swift 6, SwiftUI, Async/Await & Actors (Strict Concurrency 🧵)
- Pragmatic MVP Architecture (No heavy external frameworks 🚫)
```

```text
MacOSCleaner/
├── App/                        # App entry point, Main window & Sidebar navigation
├── Domains/                    # Business logic adapters (LaunchServiceManager, Uninstaller Engine)
├── Features/                   # Beautiful SwiftUI views & modules (Dashboard, Cleanup, Settings)
├── Infrastructure/             # Low-level system services (CommandRunner, SafetyManager, TrashManager)
├── Models/                     # Value types, operational state objects, and shared models
└── Resources/                  # Local assets, helper bash scripts, and configs
```

---

## 🛠️ Quick Start & Build

### Requirements
- Xcode 16+ 🛠️
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 📦

### Commands
Generate and run the project:
```bash
xcodegen
open MacOSCleaner.xcodeproj
# Press Cmd + R to run, Cmd + U to test! 🧪
```

---

## ✍️ Code Signing & Diagnostics
- **Personal Use:** Ad-hoc signing is perfectly fine! Run:
  ```bash
  codesign --force --deep --sign - "/Applications/MacOSCleaner.app"
  ```
- **Diagnostics:** View live app logs in macOS native `Console.app` under subsystem `OSLog`. 📑
- **Recovery:** Just "Put Back" from system Trash if you deleted something by mistake! 🗑️

---

## 🤝 Feedback & Contributions
Found a bug 🐛 or want to suggest a cool new feature 💡? Feel free to [open an issue](https://github.com/AlexTkDev/MacOSCleaner/issues)! Let's build a better cleaner together! ✨

---

## 📄 License
Licensed under **Custom Non-Commercial & Non-Embedding License** 🚫💼
* **Yes:** Study, fork, and run for personal, educational, non-commercial use.
* **No:** Commercial use, sale, or embedding into other libraries/products. See [LICENSE](LICENSE) for details. 📖