# macOS Cleaner GUI

[![License: Custom Non-Commercial](https://img.shields.io/badge/License-Custom%20NC-orange.svg)](LICENSE)

Native macOS application (Swift + SwiftUI) for safe cache cleaning, LaunchAgents management, and application removal.

## Features (MVP)

- **Cleanup:** Safely remove user caches, logs, temporary files, Xcode DerivedData, Android Studio caches, Homebrew cache, and more.
- **Startup Services:** Manage (scan, enable, disable) `~/Library/LaunchAgents`.
- **Application Removal:** Drag-and-drop `.app` bundles to remove them along with their related files (moves everything safely to the Trash).

## Safety First

- **Reversible Operations:** No permanent deletion. All files are moved to the Trash (`trashItem(at:)`).
- **Protected Paths:** Built-in safeguards prevent accidental deletion of system directories (`/System`, `/Library`), Apple services, and critical data.
- **Transactions:** JSON append-only journal for tracking all operations and supporting rollback/recovery.

## Architecture

- **Platform:** macOS (Native)
- **Language:** Swift 6
- **UI:** SwiftUI (State-driven)
- **Concurrency:** Swift Concurrency (async/await, actors)
- **Design:** Pragmatic MVP (no plugin frameworks, no dynamic policy engines, no unnecessary abstractions)

## Project Structure

```text
MacOSCleaner/
├── App/                          # Точка входа и навигация
├── Domains/                      # Бизнес-логика и адаптеры
│   └── Cleanup/
│       └── ShellCleanupAdapter.swift # Адаптер для shell-скрипта
├── Features/                     # UI модули (SwiftUI)
│   ├── Cleanup/
│   │   ├── CleanupView.swift     # Экран очистки (иерархический список)
│   │   └── CleanupViewModel.swift
│   └── ...
├── Infrastructure/               # Системные сервисы (CommandRunner, SafetyManager)
├── Models/                       # DTO и доменные модели
├── State/                        # Стейт-машины и управление состоянием
├── Resources/                    # Ассеты и shell-скрипты
├── MacOSCleanerTests/            # Юнит-тесты
├── project.yml                   # Конфигурация XcodeGen
└── MacOSCleaner.xcodeproj        # Генерируемый проект
```

## Development & Building

### Requirements
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (для управления проектом)

### Project Generation (XcodeGen)
Этот проект использует **XcodeGen** для управления `.xcodeproj`. Не редактируйте настройки проекта напрямую в Xcode, так как они будут перезаписаны при следующей генерации. Все изменения вносятся в `project.yml`.

Для генерации или обновления проекта выполните в корневой папке проекта:
```bash
xcodegen
```

### Build Instructions
1. Сгенерируйте проект с помощью `xcodegen`.
2. Откройте `MacOSCleaner.xcodeproj`.
3. Соберите и запустите (`Cmd + R`).

### Running Tests
- **In Xcode:** `Cmd + U`.
- **In Terminal:** 
  ```bash
  xcodegen && xcodebuild test -scheme MacOSCleaner -destination 'platform=macOS'
  ```

*(Note: The core cleanup script and its original README can be found in `MacOSCleaner/Resources/Scripts/`)*

## Recovery & Diagnostics

- **File Recovery:** Since all deleted files are moved to the macOS Trash, you can restore them simply by opening the Trash, right-clicking the file, and selecting "Put Back".
- **LaunchAgents Recovery:** Disabled services can be re-enabled through the "Startup Services" interface.
- **Diagnostics:** The application uses `OSLog` for internal logging. Errors and operation states can be monitored via the `Console.app`.

## Security

- Runs with Hardened Runtime enabled.
- Uses path standardization and symlink validation to prevent escaping the safe bounds.
- Refuse list denies access to critical system files.

## License

Licensed under a custom **Non-Commercial and Non-Embedding License**.

* **Permitted:** Running the application for personal, educational, and non-commercial purposes. Viewing, studying, and forking the code.
* **Prohibited:** Selling or commercializing the application or its code; using it for revenue-generating activities; embedding or integrating the code into other products, libraries, or services.

See [LICENSE](LICENSE) for full details.
