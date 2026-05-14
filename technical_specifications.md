# Техническое задание — macOS Cleaner GUI

## Версия

v1.0 — Pragmatic MVP Architecture

## Платформа

macOS 26.0+

## Тип приложения

Native macOS Application (Swift + SwiftUI)

## Distribution

Direct Download
Hardened Runtime
Без App Sandbox

---

# 1. Цель проекта

Создать нативное macOS-приложение для:

* безопасной очистки кэшей и временных файлов
* управления пользовательскими LaunchAgents
* удаления приложений и связанных файлов

Приложение ориентировано на:

* безопасность
* predictability
* rollback/recovery
* low resource usage
* native macOS UX

---

# 2. Scope MVP

## Cleanup

* User caches
* Logs
* Temporary files
* Xcode DerivedData
* Android Studio caches
* Homebrew cache
* Browser caches

## Startup Services

Только:

```text
~/Library/LaunchAgents
```

Поддержка:

* scan
* disable
* enable

Без permanent delete в MVP.

## Application Removal

* drag-and-drop `.app`
* поиск связанных файлов
* move to Trash

---

# 3. Out Of Scope

Запрещено в MVP:

* `/System`
* `/Library` modification
* root LaunchDaemons
* SIP bypass
* permanent delete
* plugin system
* telemetry
* cloud sync
* auto-cleanup daemon
* App Store distribution
* AI functionality

---

# 4. Технологический стек

| Component    | Technology        |
| ------------ | ----------------- |
| Language     | Swift 6           |
| UI           | SwiftUI           |
| Concurrency  | Swift Concurrency |
| Architecture | State-driven      |
| Persistence  | JSON journal      |
| Logging      | OSLog             |
| Charts       | SwiftUI Charts    |
| Distribution | Direct Download   |

---

# 5. Архитектурные принципы

---

## 5.1 Native First

Core logic реализуется на Swift.

Shell script используется только как adapter layer.

---

## 5.2 Safety First

Все destructive operations:

* reversible
* validated
* logged

Permanent delete запрещён.

---

## 5.3 Pragmatic MVP

Запрещено premature abstraction.

Никаких:

* plugin frameworks
* enterprise telemetry
* distributed event systems
* dynamic policy engines

---

## 5.4 Vertical Slice Development

Каждая версия:

* complete
* usable
* shippable

---

# 6. Архитектура проекта

```text
MacOSCleaner/
├── App/
├── Features/
│   ├── Dashboard/
│   ├── Cleanup/
│   ├── StartupServices/
│   ├── Uninstaller/
│   └── Settings/
├── Domains/
│   ├── Cleanup/
│   ├── Startup/
│   └── Removal/
├── Infrastructure/
│   ├── CommandRunner.swift
│   ├── FileScanner.swift
│   ├── FileSystemService.swift
│   ├── TrashManager.swift
│   ├── SafetyManager.swift
│   └── TransactionStore.swift
├── State/
│   └── CleanupStateMachine.swift
├── Models/
└── Resources/
    └── Scripts/
```

---

# 7. Core Infrastructure

---

## 7.1 CommandRunner

Единая точка запуска процессов.

Запрещён прямой `Process()` вне инфраструктурного слоя.

```swift
actor CommandRunner {
    func run(
        command: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> CommandResult
}
```

### Требования

* timeout
* cancellation
* stdout/stderr capture
* exit code handling

---

## 7.2 FileScanner

```swift
actor FileScanner {
    func scan(_ url: URL) async throws -> [ScanResult]
}
```

### Требования

* batching
* cooperative cancellation
* throttling
* symlink resolution

---

## 7.3 TrashManager

Все delete операции:

```swift
FileManager.trashItem(at:)
```

Permanent delete запрещён.

---

## 7.4 SafetyManager

### Обязанности

* path normalization
* symlink protection
* protected path validation

### Refuse list

```text
/
~/Documents
~/.ssh
~/.gnupg
/System
/Library
/usr
/bin
/private
```

---

# 8. Cleanup Domain

---

## 8.1 CleanupProvider

```swift
protocol CleanupProvider {
    func execute() async throws -> AsyncStream<CleanupEvent>
}
```

---

## 8.2 ShellCleanupAdapter

Wrapper над:

```text
macos-cache-cleanup.sh
```

---

## 8.3 Script Requirements

Скрипт должен поддерживать:

```bash
--json
--gui
--dry-run
```

---

## 8.4 JSON Streaming Format

```json
{
  "event":"item",
  "name":"Homebrew Cache",
  "size_mb":420,
  "risk":"safe"
}
```

stdout flush после каждой строки.

---

# 9. Startup Services Domain

---

## Scope

Только:

```text
~/Library/LaunchAgents
```

---

## LaunchServiceManager

```swift
actor LaunchServiceManager {
    func scan() async throws -> [StartupService]
    func disable(_ service: StartupService) async throws
    func enable(_ service: StartupService) async throws
}
```

---

## Supported Operations

Разрешено:

* bootout
* disable
* enable

Запрещено:

* permanent delete
* root daemons manipulation

---

## Runtime Detection

Используется:

```bash
launchctl print
launchctl list
```

---

# 10. Application Removal Domain

---

## UninstallerService

Поддержка:

* drag-and-drop `.app`
* bundle identifier extraction
* related files scanning
* move to Trash

---

## Supported Paths

```text
~/Library/Application Support
~/Library/Caches
~/Library/Preferences
~/Library/Logs
~/Library/Containers
~/Library/Saved Application State
```

---

# 11. State Machine

```swift
enum CleanupState {
    case idle
    case scanning
    case preview
    case executing
    case completed
    case failed(Error)
    case cancelled
}
```

---

## Правила

* explicit transitions only
* cancellation-safe
* invalid transitions denied

---

# 12. Risk Model

```swift
enum OperationRisk {
    case safe
    case moderate
    case dangerous
    case protected
}
```

---

## Rules

### safe

* caches
* logs

### moderate

* launch agent disable

### dangerous

* container cleanup
* unknown vendor cleanup

### protected

* Apple services
* system vendors

---

# 13. Transactions & Recovery

---

## CleanupTransaction

```swift
struct CleanupTransaction {
    let id: UUID
    let timestamp: Date
    let operations: [OperationRecord]
}
```

---

## Recovery

Поддержка:

* restore from Trash
* re-enable LaunchAgent

---

## Persistence

JSON append-only journal.

Без SwiftData в MVP.

---

# 14. UI/UX

---

## Window

```text
minWidth: 1000
minHeight: 700
```

---

## Sidebar

* Dashboard
* Cleanup
* Startup Services
* Uninstaller
* Settings

---

## Toolbar

* Search
* Refresh
* Current risk indicator

---

## Real-Time Activity Panel

Отображает:

* scanning
* cleaning
* disabling service
* moving to Trash

---

## Drag & Drop

```swift
.dropDestination(for: URL.self)
```

---

# 15. Security

---

## Runtime

* Hardened Runtime
* notarized build
* no sandbox

---

## Path Protection

Обязательны:

* standardized paths
* symlink validation
* protected directories checks

---

## Delete Policy

Только:

```swift
trashItem(at:)
```

---

## Protected Vendors

Запрещено удаление:

* `com.apple.*`

Warning-required:

* Docker
* OrbStack
* Tailscale
* JetBrains
* Adobe
* Microsoft

---

# 16. Performance Targets

| Metric           | Target   |
| ---------------- | -------- |
| App launch       | < 2 sec  |
| UI interactive   | < 500 ms |
| Cleanup feedback | < 300 ms |
| Idle RAM         | < 150 MB |
| App size         | < 80 MB  |

---

# 17. Testing

---

## Обязательно

Все infrastructure services:

* protocol-based
* mockable

---

## Test Types

### Unit Tests

* cleanup logic
* safety validation
* state machine

### Integration Tests

* sandbox filesystem
* shell adapter
* launchctl wrapper

### UI Tests

* navigation
* drag-and-drop
* cleanup flow

---

# 18. Roadmap

---

# v1 — Core Cleanup MVP

## Features

* Cleanup GUI
* Shell adapter
* Dry-run
* Progress streaming
* State machine
* SafetyManager
* TrashManager
* JSON transactions

---

# v2 — Startup Services

## Features

* LaunchAgents scan
* enable/disable
* recovery
* transaction rollback

---

# v3 — Dashboard & Analytics

## Features

* disk usage charts
* cleanup history
* diagnostics view

---

# v4 — Native Cleanup Engine

## Features

* replace shell logic with native Swift providers
* rule-based cleanup engine

---

# v5 — Experimental Features

## Features

* remnants scanner
* advanced diagnostics

Disabled by default.

---

# 19. Acceptance Criteria

---

## Architecture

* shell script не является core logic
* все delete операции reversible
* state machine explicit
* infrastructure centralized

---

## Security

* protected paths validated
* symlink escape impossible
* permanent delete отсутствует
* Apple services protected

---

## Stability

* cancellation safe
* no UI freeze during scan
* launchctl failures handled gracefully

---

## Performance

* responsive UI during scans
* low idle RAM usage
* bounded filesystem scanning

---

# 20. Deliverables

1. Xcode Project
2. Signed `.app`
3. Modified cleanup script
4. Unit + integration tests
5. JSON transaction journal
6. README:

   * architecture
   * recovery
   * diagnostics
   * build instructions
