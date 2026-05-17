# macOS Cleaner GUI

[![License: Custom Non-Commercial](https://img.shields.io/badge/License-Custom%20NC-orange.svg)](LICENSE)

Native macOS application (Swift + SwiftUI) for safe cache cleaning, LaunchAgents management, and application uninstallation.

## Features

- **Cleanup:** Safely remove user caches, logs, temporary files, Xcode DerivedData, Android Studio caches, Homebrew cache, and more.
- **Startup Services:** Manage (scan, enable, disable) `~/Library/LaunchAgents`.
- **Application Uninstallation:** Drag-and-drop `.app` bundles to remove them along with associated files (everything is moved safely to the Trash).

## Safety First

- **Reversible Operations:** No permanent deletion. All files are moved to the system Trash (`trashItem(at:)`).
- **Protected Paths:** Built-in safeguards prevent accidental deletion of system directories (`/System`, `/Library`), Apple services, and critical data.
- **Transactions:** JSON append-only journal for tracking all operations and supporting state recovery.

## Architecture

- **Platform:** macOS (Native)
- **Language:** Swift 6
- **UI:** SwiftUI (State-driven)
- **Concurrency:** Swift Concurrency (async/await, actors)
- **Design:** Pragmatic MVP (no heavy frameworks, minimal abstractions)

## Project Structure

```text
MacOSCleaner/
├── App/                          # App entry point and navigation
├── Domains/                      # Business logic and adapters
├── Features/                     # UI modules (SwiftUI)
│   ├── Cleanup/
│   ├── Dashboard/
│   ├── Settings/
│   └── ...
├── Infrastructure/               # System services (CommandRunner, SafetyManager)
├── Models/                       # Domain models and DTOs
├── State/                        # State machines
├── Resources/                    # Assets and scripts
├── MacOSCleanerTests/            # Unit tests
├── project.yml                   # XcodeGen configuration
└── MacOSCleaner.xcodeproj        # Generated project file
```

## Development & Building

### Requirements
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Project Generation
This project uses **XcodeGen** to manage the `.xcodeproj`. Do not edit project settings directly in Xcode as they will be overwritten upon regeneration. Make changes in `project.yml` instead.

To generate or update the project, run the following in the project root:
```bash
xcodegen
```

### Build Instructions
1. Generate the project: `xcodegen`.
2. Open `MacOSCleaner.xcodeproj`.
3. Build and Run (`Cmd + R`).

### Running Tests
- **In Xcode:** `Cmd + U`.
- **In Terminal:** 
  ```bash
  xcodegen && xcodebuild test -scheme MacOSCleaner -destination 'platform=macOS'
  ```

## Recovery & Diagnostics

- **File Recovery:** Since all deleted files are moved to the macOS Trash, you can restore them by opening the Trash, right-clicking the file, and selecting "Put Back".
- **LaunchAgents Recovery:** Disabled services can be re-enabled through the "Startup Services" interface.
- **Diagnostics:** The application uses `OSLog` for internal logging. Monitor via `Console.app`.

## Security

- Runs with Hardened Runtime enabled.
- Uses path standardization and symlink validation to prevent directory traversal outside of safe boundaries.
- Refuse list denies access to critical system files.

## License

Licensed under a custom **Non-Commercial and Non-Embedding License**.

* **Permitted:** Running the application for personal, educational, and non-commercial purposes. Viewing, studying, and forking the code.
* **Prohibited:** Selling or commercializing the application or its code; using it for revenue-generating activities; embedding or integrating the code into other products, libraries, or services.

See [LICENSE](LICENSE) for full details.
