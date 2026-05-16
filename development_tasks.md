# EXECUTION SPECIFICATION

# Project

macOS Cleaner GUI

---

# Global Rules

## Architecture Rules

* Use Swift 6
* Use SwiftUI only
* Use native macOS APIs
* No AppKit unless unavoidable
* No third-party dependencies in MVP
* No Combine
* Use Swift Concurrency only
* Use actors for mutable shared state
* No singleton services
* No direct `Process()` outside CommandRunner
* No permanent delete
* No root privileges
* No App Sandbox
* No plugin architecture
* No premature abstraction

---

# Coding Rules

## Code Style

* Small files
* One responsibility per type
* Prefer structs over classes
* Prefer composition over inheritance
* Avoid generic-heavy abstractions
* Avoid protocol explosion
* Avoid unnecessary ViewModels

---

## SwiftUI Rules

* State-driven UI
* Use `@Observable`
* Avoid massive Views
* Split reusable components
* No business logic in Views

---

## Concurrency Rules

* Use async/await
* Use actors for shared mutable state
* Use Task cancellation correctly
* Never block MainActor
* No detached tasks unless required

---

# Repository Structure

```text
MacOSCleaner/
├── App/
├── Features/
├── Domains/
├── Infrastructure/
├── Models/
├── State/
├── Resources/
├── Tests/
└── Scripts/
```

---

# Execution Strategy

Project must be implemented as vertical slices.

Each task must:

* compile
* run
* be testable
* not break previous functionality

---

# PHASE 1 — FOUNDATION

---

# TASK-001 [x]

## Title

Create base Xcode project

## Goal

Initialize native macOS SwiftUI application.

## Requirements

* Swift 6
* macOS 26.0+
* SwiftUI App lifecycle
* Hardened Runtime ready
* No sandbox

## Deliverables

* Working `.xcodeproj`
* Buildable app
* Empty sidebar navigation

## Acceptance Criteria

* App launches
* Sidebar visible
* No warnings
* No force unwraps

---

# TASK-002 [x]

## Title

Implement application navigation

## Goal

Create NavigationSplitView layout.

## Requirements

Sidebar items:

* Dashboard
* Cleanup
* Startup Services
* Uninstaller
* Settings

## Deliverables

* Sidebar navigation
* Empty placeholder screens

## Acceptance Criteria

* Navigation works
* State preserved
* No UI glitches

---

# TASK-003 [x]

## Title

Create core models

## Goal

Implement shared models.

## Required Models

```swift
CleanupItem
ScanResult
OperationRisk
CleanupTransaction
StartupService
```

## Acceptance Criteria

* Codable support
* Sendable support
* No reference cycles

---

# PHASE 2 — INFRASTRUCTURE

---

# TASK-004 [x]

## Title

Implement CommandRunner actor

## Goal

Centralize external process execution.

## Requirements

Features:

* async execution
* stdout capture
* stderr capture
* timeout
* cancellation support

## Restrictions

* No direct Process usage outside this actor

## Acceptance Criteria

* Unit tested
* Cancellation works
* Timeout works

---

# TASK-005 [x]

## Title

Implement SafetyManager

## Goal

Prevent dangerous filesystem operations.

## Requirements

Checks:

* path normalization
* symlink resolution
* protected paths
* refuse list

## Refuse Paths

```text
/
/System
/Library
/usr
/bin
/private
~/.ssh
~/.gnupg
~/Documents
```

## Acceptance Criteria

* Rejects dangerous paths
* Rejects symlink escapes
* Fully unit tested

---

# TASK-006 [x]

## Title

Implement TrashManager

## Goal

Centralize safe delete operations.

## Requirements

Use only:

```swift
FileManager.trashItem(at:)
```

## Restrictions

* Permanent delete forbidden

## Acceptance Criteria

* Restore possible from Trash
* Errors handled correctly

---

# TASK-007 [x]

## Title

Implement FileScanner actor

## Goal

Create cancellable filesystem scanner.

## Requirements

Features:

* recursive scanning
* batching
* throttling
* cancellation-safe

## Acceptance Criteria

* No UI freezes
* Large directories supported
* Cancellation responsive

---

# PHASE 3 — CLEANUP DOMAIN

---

# TASK-008 [x]

## Title

Create CleanupStateMachine

## Goal

Formalize cleanup lifecycle.

## States

```swift
idle
scanning
preview
executing
completed
failed
cancelled
```

## Acceptance Criteria

* Explicit transitions only
* Invalid transitions denied
* Unit tested

---

# TASK-009

## Title

Implement ShellCleanupAdapter

## Goal

Connect existing shell cleanup script.

## Requirements

Supported flags:

```bash
--json
--gui
--dry-run
```

## Restrictions

* Shell script is adapter only
* No business logic in shell

## Acceptance Criteria

* JSON streaming works
* Progress updates visible
* Cancellation works

---

# TASK-010 [x]

## Title

Implement cleanup transaction journal

## Goal

Track reversible operations.

## Persistence

JSON append-only journal.

## Acceptance Criteria

* Transactions persisted
* Restore metadata available
* Corruption-safe writes

---

# TASK-011 [x]

## Title

Create Cleanup UI

## Goal

Implement full cleanup flow.

## Features

* scan
* dry-run preview
* execute cleanup
* progress updates
* risk indicators

## Acceptance Criteria

* No UI blocking
* Progress updates live
* Errors displayed correctly

---

# PHASE 4 — STARTUP SERVICES

---

# TASK-012

## Title

Implement LaunchServiceManager

## Goal

Manage user LaunchAgents safely.

## Scope

Only:

```text
~/Library/LaunchAgents
```

## Supported Operations

* scan
* disable
* enable

## Forbidden

* root daemons
* permanent delete

## Acceptance Criteria

* launchctl integration stable
* failures handled gracefully

---

# TASK-013

## Title

Create Startup Services UI

## Goal

Visual management of LaunchAgents.

## Features

* loaded state
* disabled state
* enable/disable buttons
* risk indicators

## Acceptance Criteria

* State updates correctly
* No stale UI state

---

# PHASE 5 — UNINSTALLER

---

# TASK-014

## Title

Implement UninstallerService

## Goal

Remove applications safely.

## Features

* drag-and-drop `.app`
* bundle ID extraction
* related files scanning
* move to Trash

## Acceptance Criteria

* App detection works
* Related files detected
* No protected paths touched

---

# TASK-015

## Title

Create Uninstaller UI

## Goal

Visual uninstall workflow.

## Features

* drag-and-drop area
* related files tree
* risk indicators
* confirmation dialogs

## Acceptance Criteria

* Drag-and-drop stable
* Preview accurate
* Cleanup reversible

---

# PHASE 6 — DASHBOARD

---

# TASK-016

## Title

Implement Dashboard

## Goal

Show cleanup statistics.

## Features

* disk usage
* cleanup history
* recent operations

## Acceptance Criteria

* Fast rendering
* No blocking filesystem operations

---

# PHASE 7 — TESTING

---

# TASK-017

## Title

Create infrastructure test suite

## Goal

Ensure infrastructure reliability.

## Coverage

* CommandRunner
* SafetyManager
* TrashManager
* FileScanner

## Acceptance Criteria

* High coverage
* Sandbox-only tests

---

# TASK-018

## Title

Create integration tests

## Goal

Validate real workflows.

## Coverage

* cleanup flow
* launchctl flow
* uninstall flow

## Acceptance Criteria

* Runs on clean macOS install
* No destructive operations

---

# Definition Of Done

Task считается завершённой только если:

* Builds successfully
* No warnings
* No crashes
* Tests pass
* Cancellation works
* No MainActor blocking
* No unsafe filesystem operations
* Feature manually tested

---

# Forbidden Patterns

Agents must NOT introduce:

* singleton managers
* global mutable state
* force unwraps
* massive God objects
* business logic in Views
* direct filesystem delete
* direct Process usage
* callback-based async code
* Combine
* RxSwift
* dependency injection frameworks

---

# Performance Constraints

* App launch < 2 sec
* No UI freezes
* Idle RAM < 150 MB
* Responsive during scans

---

# Security Constraints

Forbidden:

* permanent delete
* root escalation
* SIP bypass
* system directory modification

Required:

* symlink validation
* protected path checks
* reversible operations

---

# Final Deliverables

* Buildable Xcode project
* Signed `.app`
* Unit tests
* Integration tests
* JSON transaction journal
* Documentation
* Hardened Runtime compatible build
