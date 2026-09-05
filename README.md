<div align="center">
  <h1 align="center">
    <img src=".github/logo.png?v=3" alt="MacOS Cleaner Logo" width="130"><br>
    <b style="font-size: 2rem">MacOS Cleaner</b>
  </h1>
  <p>
    Free, native, privacy-first cleaner and application uninstaller for macOS.<br>
    Built with Swift 6 and SwiftUI. Moves files to Trash by default instead of permanently deleting them.
  </p>

  <p>
    <small>Requirements: macOS 26.0 or later. Apple Silicon only (Intel Macs are not supported).</small>
  </p>

  <p>
    <a href="https://github.com/AlexTkDev/MacOSCleaner/releases/latest"><img src="https://img.shields.io/badge/Direct_Download-.dmg-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download DMG"></a>
    &nbsp;
    <a href="https://alextkdev.github.io/MacOSCleaner/"><img src="https://img.shields.io/badge/Official_Website-Visit_Site-238636?style=for-the-badge&logo=safari&logoColor=white" alt="Official Website"></a>
  </p>

  <p>
    <a href="https://github.com/AlexTkDev/MacOSCleaner/releases/tag/2.2.0"><img src="https://img.shields.io/badge/Release-v2.2.0-007AFF?style=flat&logo=apple&logoColor=white" alt="Release"></a>
    <a href="https://apple.com"><img src="https://img.shields.io/badge/macOS-26%2B-black?style=flat&logo=apple&logoColor=white" alt="macOS 26+"></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-FA7343?style=flat&logo=swift&logoColor=white" alt="Swift 6"></a>
    <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-Native-0071E3?style=flat&logo=swift&logoColor=white" alt="SwiftUI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3%2BCommons-blue?style=flat" alt="License"></a>
  </p>

  <p>
    <a href="#features">✨ Features</a> &nbsp;•&nbsp;
    <a href="#screenshots">📸 Screenshots</a> &nbsp;•&nbsp;
    <a href="#build-from-source">🛠️ Build from Source</a> &nbsp;•&nbsp;
    <a href="https://github.com/AlexTkDev/MacOSCleaner/wiki">📖 Documentation</a>
  </p>
</div>

---

<a id="safety"></a>
## 🛡️ Safety and Architecture

| Principle | Technical Implementation |
| :--- | :--- |
| **No Telemetry** | No background daemons, analytics SDKs, or remote loggers. All scanning runs locally without network access. |
| **Trash-First** | Files are moved to macOS Trash via `trashItem(at:)` when supported, preserving native file recovery. |
| **Protected Paths** | Hardcoded blocklists protect SIP paths, `/System`, `/Library`, `/usr`, `~/.ssh`, and user document directories. |
| **Open Core** | Swift 6 codebase with strict concurrency, actors, and structured task groups. Core engine and heuristics are inspectable. |
| **On-Device AI** | Checksums, hashes, and `FoundationModels` file explanations execute strictly on-device. |
| **Native Runtime** | Built in Swift 6 and SwiftUI with Liquid Glass materials. No Electron or WebKit container overhead. |

---

<a id="screenshots"></a>
## 📸 Screenshots

<p align="center">
  <img src="assets/screenshots/Dashboard_v2_2.png" width="48%" alt="Dashboard">
  <img src="assets/screenshots/Uninstaller_v2_2.png" width="48%" alt="App Uninstaller">
</p>
<p align="center">
  <img src="assets/screenshots/Cleanup_Scan_v2_2.png" width="48%" alt="Smart Cleanup">
  <img src="assets/screenshots/Processes_v2_2.png" width="48%" alt="Process Manager">
</p>

<p align="center">
  <a href="assets/screenshots">View high-resolution screenshots</a>
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

<a id="features"></a>
## ✨ Features

- **Smart Cleanup:** scans 55+ categories across system caches, 275+ applications, 85+ developer toolchains & package managers (Xcode, Docker, `uv`, `mise`, Rust, Go, Python, Node), local AI models & coding assistants (Claude Code, Ollama, MLX, Hugging Face, WhisperKit), and safe Time Machine snapshot thinning (`thinlocalsnapshots`).
- **Forensic Uninstaller:** inspects 30 evidence types (Bundle ID, Team ID, Spotlight metadata, Launch Services) to trace remnants across 1,800+ known application paths and heuristics, with standalone orphaned residuals discovery, confidence score tiers, post-uninstall review sheets, and root-level helper removal.
- **Duplicate Finder:** identifies duplicate files through a 3-stage pipeline (file size matching, 4 KB header checksum, full SHA-256 verification).
- **Disk Space Analyzer:** hierarchical folder drill-down with breadcrumb navigation, honest APFS allocated block sizing (`totalFileAllocatedSize`), Quick Look previews (`Space`), recursive category filters (Videos, Audio, Photos, Documents, Archives), and dataless iCloud item skip protection.
- **Process and Service Manager:** monitors live CPU and RAM usage with termination safeguards for critical processes (`kernel_task`, `launchd`), plus LaunchAgents and LaunchDaemons toggling.
- **Native System Integrations:** on-device `FoundationModels` explanations for unknown caches, Siri and App Intents automation, Liquid Glass materials with keyboard navigation (`⌘,`, `⌘C`, `⌘F`, `⌘R`, `⌘⌫`), and 10 language localizations.

Complete feature breakdowns and path specifications are documented in the [MacOSCleaner Wiki](https://github.com/AlexTkDev/MacOSCleaner/wiki).

---

<a id="build-from-source"></a>
## 🛠️ Build from Source

**Prerequisites:** macOS 26.0+, Xcode 18+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/AlexTkDev/MacOSCleaner.git
cd MacOSCleaner/MacOSCleaner
xcodegen
open MacOSCleaner.xcodeproj
```

Build and run with **⌘R**, or run tests with **⌘U**.

> *Note: Public source builds use the public fallback cleanup catalog.*

---

<a id="community"></a>
## ⭐️ Support & Community

If you find MacOS Cleaner useful, please consider giving it a ⭐️ on GitHub. It helps more users discover the project and directly supports ongoing development.

- <a href="https://github.com/AlexTkDev/MacOSCleaner/stargazers"><img src="https://img.shields.io/badge/GitHub-⭐️_Star_Repository-gold?style=flat&logo=github&logoColor=black" alt="Star Repository" align="absmiddle"></a> — [Star the repository](https://github.com/AlexTkDev/MacOSCleaner/stargazers) and watch releases for update notifications.
- <a href="https://github.com/AlexTkDev/MacOSCleaner/discussions"><img src="https://img.shields.io/badge/Discussions-Forum-181717?style=flat&logo=discourse&logoColor=white" alt="Discussions" align="absmiddle"></a> — [Ask questions, propose features, and share feedback.](https://github.com/AlexTkDev/MacOSCleaner/discussions)
- <a href="https://github.com/AlexTkDev/MacOSCleaner/issues"><img src="https://img.shields.io/badge/Issues-Tracker-E5534B?style=flat&logo=instabug&logoColor=white" alt="Issue Tracker" align="absmiddle"></a> — [Report bugs or suggest rule improvements.](https://github.com/AlexTkDev/MacOSCleaner/issues)
- <a href="https://github.com/AlexTkDev/MacOSCleaner/wiki"><img src="https://img.shields.io/badge/Wiki-Documentation-238636?style=flat&logo=gitbook&logoColor=white" alt="Documentation" align="absmiddle"></a> — [Architecture overview and developer guides.](https://github.com/AlexTkDev/MacOSCleaner/wiki)
- <a href="https://cursor.com/codebase/alextkdev/MacOSCleaner/tree/release"><img src="https://img.shields.io/badge/Cursor-Codebase-000000?style=flat&logo=cursor&logoColor=white" alt="Cursor Codebase" align="absmiddle"></a> — [Explore repository online and open in Cursor.](https://cursor.com/codebase/alextkdev/MacOSCleaner/tree/release)

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
      <a href="https://github.com/AlexTkDev"><img src="https://img.shields.io/badge/GitHub-Follow_%40AlexTkDev-181717?style=flat&logo=github" alt="Follow on GitHub"></a>
      <a href="https://orcid.org/0009-0002-8907-5406"><img src="https://img.shields.io/badge/ORCID-0009--0002--8907--5406-A6CE39?style=flat&logo=orcid&logoColor=white" alt="ORCID"></a>
      <a href="https://ko-fi.com/alextkdev"><img src="https://img.shields.io/badge/Ko--fi-Support-F16061?style=flat&logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
      <a href="DONATE.md"><img src="https://img.shields.io/badge/Donate-Crypto-F7931A?style=flat&logo=bitcoin&logoColor=white" alt="Donate"></a>
    </td>
  </tr>
</table>

> Citation reference: [`CITATION.cff`](CITATION.cff)

---

## 📄 License

Dual-licensed:
- **[GNU GPLv3 + Commons Clause v1.0](LICENSE)** for personal, non-commercial use, testing, and open-source contributions. Commercial resale and commercial re-licensing are prohibited.
- **Commercial License** for enterprise, commercial, or proprietary distribution. [Contact the author](https://github.com/AlexTkDev) for licensing inquiries.

> **Trademark Notice**: The license does not grant permission to use the project name ("MacOSCleaner"), logos, or branding in derivative works.
