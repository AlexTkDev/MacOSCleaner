# macOS Cleaner GUI

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
├── App/
│   ├── MacOSCleanerApp.swift     # Точка входа в приложение
│   ├── RootView.swift            # Главный экран с навигацией
│   └── ContentView.swift         # Вспомогательный View
├── Features/                     # Функциональные модули (UI)
│   ├── Cleanup/
│   │   └── CleanupView.swift     # Модуль очистки
│   ├── Dashboard/
│   │   └── DashboardView.swift   # Панель состояния
│   ├── Settings/
│   │   └── SettingsView.swift    # Настройки
│   ├── StartupServices/
│   │   └── StartupServicesView.swift # Автозагрузка
│   └── Uninstaller/
│       └── UninstallerView.swift # Удаление приложений
├── Infrastructure/               # Инфраструктурный слой
│   ├── CommandRunner.swift       # Запуск внешних процессов (Actor)
│   └── SafetyManager.swift        # Проверка безопасности путей
├── Models/                       # Модели данных
│   ├── CleanupItem.swift         # Элемент очистки
│   ├── CleanupTransaction.swift  # Транзакция очистки
│   ├── NavigationItem.swift      # Модель навигации
│   ├── OperationRecord.swift     # Запись об операции
│   ├── OperationRisk.swift       # Уровни риска
│   ├── ScanResult.swift          # Результат сканирования
│   └── StartupService.swift      # Служба автозагрузки
├── Resources/                    # Ресурсы
│   ├── Assets.xcassets           # Медиа-файлы
│   └── Scripts/                  # Скрипты-адаптеры
│       ├── macos-cache-cleanup.sh # Скрипт очистки (legacy/adapter)
│       └── README.md             # Документация скрипта
├── MacOSCleanerTests/            # Тесты
│   ├── CommandRunnerTests.swift  # Тесты CommandRunner
│   └── SafetyManagerTests.swift  # Тесты SafetyManager
└── MacOSCleaner.xcodeproj        # Проект Xcode
```

## Building the Project

### Requirements
- Xcode 16+
- macOS (as specified in the Xcode project)

### Build Instructions
1. Open `MacOSCleaner.xcodeproj` in Xcode.
2. Select the `MacOSCleaner` scheme.
3. Build and Run (`Cmd + R`).

### Running Tests
To run the unit tests:
- **In Xcode:** Press `Cmd + U` or go to `Product` -> `Test`.
- **In Terminal:** 
  ```bash
  cd MacOSCleaner
  xcodebuild test -scheme MacOSCleaner -destination 'platform=macOS'
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
