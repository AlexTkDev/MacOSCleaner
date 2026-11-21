import XCTest
@testable import MacOSCleaner

@MainActor
final class CleanupTrashTests: XCTestCase {
    private var fileSystemContext: FileSystemContext!
    private var trashDirectory: URL!
    private var coordinator: CleanupCoordinator!
    private var settings: AppSettings!
    private var engine: CleanupEngine!
    private var journal: TransactionJournal!
    private var itemManager: CleanupItemManager!
    private var trashManager: TrashManager!
    private var savedEmptyTrashSetting: Bool = false

    override func setUp() async throws {
        try await super.setUp()
        fileSystemContext = try FileSystemContext.isolatedTestRoot()
        trashDirectory = fileSystemContext.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)

        let safety = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        trashManager = TrashManager(safetyManager: safety, trashDirectoryURL: trashDirectory)
        engine = CleanupEngine(safetyManager: safety, fileSystemContext: fileSystemContext)

        let journalURL = fileSystemContext.homeDirectory.appendingPathComponent("transactions.jsonl")
        journal = TransactionJournal(journalURL: journalURL)

        settings = AppSettings()
        savedEmptyTrashSetting = settings.emptyTrashDuringCleanup

        itemManager = CleanupItemManager()
        coordinator = CleanupCoordinator(
            engine: engine,
            journal: journal,
            settings: settings,
            trashManager: trashManager,
            itemManager: itemManager,
            trashDirectoryURL: trashDirectory
        )
    }

    override func tearDown() async throws {
        settings?.emptyTrashDuringCleanup = savedEmptyTrashSetting
        if let root = fileSystemContext?.allowedRoots.first {
            try? FileManager.default.removeItem(at: root)
        }
        fileSystemContext = nil
        trashDirectory = nil
        coordinator = nil
        settings = nil
        engine = nil
        journal = nil
        itemManager = nil
        trashManager = nil
        try await super.tearDown()
    }

    private func waitForState(_ targetState: CleanupState, timeout: TimeInterval = 8.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if coordinator.state == targetState {
                return
            }
            if case .failed = coordinator.state {
                XCTFail("Coordinator failed with error: \(coordinator.lastError ?? "nil")")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for \(targetState), current state: \(coordinator.state)")
    }

    func testScan_emptyTrashDuringCleanup_disabledByDefault_doesNotScanTrash() async throws {
        settings.emptyTrashDuringCleanup = false
        let dummyFile = trashDirectory.appendingPathComponent("some_trash.txt")
        try "trash content".data(using: .utf8)!.write(to: dummyFile)

        coordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let trashLabel = "trash_user_label".localized
        XCTAssertFalse(itemManager.items.contains { $0.label == trashLabel },
                       "Trash must not appear in preview when emptyTrashDuringCleanup is false")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dummyFile.path),
                      "Trash items must not be touched")
    }

    func testScan_emptyTrashDuringCleanup_enabled_scansTrashAndMarksSelected() async throws {
        settings.emptyTrashDuringCleanup = true
        let file1 = trashDirectory.appendingPathComponent("file1.log")
        let subfolder = trashDirectory.appendingPathComponent("subfolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let file2 = subfolder.appendingPathComponent("file2.dat")

        try Data(repeating: 0xAA, count: 1024).write(to: file1)
        try Data(repeating: 0xBB, count: 2048).write(to: file2)

        coordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let trashLabel = "trash_user_label".localized
        guard let trashItem = itemManager.items.first(where: { $0.label == trashLabel }) else {
            XCTFail("Trash category must appear in preview when emptyTrashDuringCleanup is true")
            return
        }

        XCTAssertTrue(trashItem.isSelected, "Trash group must be selected by default")
        XCTAssertFalse(trashItem.children.isEmpty, "Trash should have children entries")
        XCTAssertTrue(trashItem.children.allSatisfy { $0.isSelected }, "All trash children should be isSelected: true")
        XCTAssertGreaterThanOrEqual(trashItem.sizeBytes, 3072)
    }

    func testExecuteCleanup_emptyTrashDuringCleanup_enabledAndSelected_permanentlyDeletesTrashContents_preservesTrashDir() async throws {
        settings.emptyTrashDuringCleanup = true
        let file1 = trashDirectory.appendingPathComponent("file1.log")
        let subfolder = trashDirectory.appendingPathComponent("subfolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let file2 = subfolder.appendingPathComponent("file2.dat")

        try Data(repeating: 0xAA, count: 1024).write(to: file1)
        try Data(repeating: 0xBB, count: 2048).write(to: file2)

        coordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let trashLabel = "trash_user_label".localized
        XCTAssertTrue(itemManager.items.first(where: { $0.label == trashLabel })?.isSelected == true)

        coordinator.executeCleanup(options: CleanupOptions(targetCategories: []))
        try await waitForState(.completed)

        // Contents of Trash must be completely deleted
        let remainingContents = (try? FileManager.default.contentsOfDirectory(atPath: trashDirectory.path)) ?? []
        XCTAssertTrue(remainingContents.isEmpty, "All contents inside ~/.Trash must be permanently deleted, remaining: \(remainingContents)")

        // .Trash folder itself must NOT be deleted
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashDirectory.path),
                      "~/.Trash folder itself must not be deleted")

        // Stats and journal verification
        XCTAssertGreaterThanOrEqual(coordinator.totalFreedBytes, 3072)
        XCTAssertTrue(coordinator.cleanedItems.contains { $0.label == trashLabel },
                      "Cleaned items must include Trash category")

        let tx = try await journal.loadAll()
        XCTAssertTrue(tx.contains { t in t.operations.contains { $0.itemPath == trashLabel && $0.status == "success" } },
                      "Journal must record successful trash emptying")
    }

    func testExecuteCleanup_partialTrashDeselect_keepsUncheckedItem() async throws {
        settings.emptyTrashDuringCleanup = true
        let keep = trashDirectory.appendingPathComponent("keep.log")
        let drop = trashDirectory.appendingPathComponent("drop.log")
        try Data(repeating: 0xAA, count: 1024).write(to: keep)
        try Data(repeating: 0xBB, count: 1024).write(to: drop)

        coordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let trashLabel = "trash_user_label".localized
        guard let parent = itemManager.items.firstIndex(where: { $0.label == trashLabel }) else {
            XCTFail("Trash group missing")
            return
        }
        guard let child = itemManager.items[parent].children.firstIndex(where: { $0.path?.hasSuffix("keep.log") == true }) else {
            XCTFail("keep.log missing from trash preview")
            return
        }
        itemManager.items[parent].children[child].isSelected = false

        coordinator.executeCleanup(options: CleanupOptions(targetCategories: []))
        try await waitForState(.completed)

        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: drop.path))
    }

    func testExecuteCleanup_emptyTrashDuringCleanup_enabledButDeselected_preservesTrash() async throws {
        settings.emptyTrashDuringCleanup = true
        let file1 = trashDirectory.appendingPathComponent("file1.log")
        try Data(repeating: 0xAA, count: 1024).write(to: file1)

        coordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let trashLabel = "trash_user_label".localized
        if let idx = itemManager.items.firstIndex(where: { $0.label == trashLabel }) {
            itemManager.items[idx].isSelected = false
        }

        coordinator.executeCleanup(options: CleanupOptions(targetCategories: []))
        try await waitForState(.completed)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path),
                      "Trash items must NOT be deleted when deselected by user")
        XCTAssertFalse(coordinator.cleanedItems.contains { $0.label == trashLabel })
    }

    func testExecuteCleanup_emptyTrashDuringCleanup_disabled_preservesTrash() async throws {
        settings.emptyTrashDuringCleanup = false
        let file1 = trashDirectory.appendingPathComponent("file1.log")
        try Data(repeating: 0xAA, count: 1024).write(to: file1)

        coordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        coordinator.executeCleanup(options: CleanupOptions(targetCategories: []))
        try await waitForState(.completed)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path),
                      "Trash items must NOT be deleted when emptyTrashDuringCleanup is false")
    }

    func testExecuteCleanup_bypassTrash_setsPermanentDeletionAndAPFSDelta() async throws {
        let savedBypass = settings.bypassTrashOnUninstall
        defer { settings.bypassTrashOnUninstall = savedBypass }
        settings.emptyTrashDuringCleanup = false
        settings.bypassTrashOnUninstall = true

        // Seed a reviewOnly installer leaf under Downloads to exercise coordinator deletion + journal fields cleanly
        let downloads = fileSystemContext.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let bigFile = downloads.appendingPathComponent("TestInstaller.dmg")
        try Data(repeating: 0xCC, count: 1024).write(to: bigFile)

        final class SequenceBox: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [Int64] = [100_000_000, 100_500_000]
            func next() -> Int64? {
                lock.withLock { values.isEmpty ? nil : values.removeFirst() }
            }
        }
        let capacityBox = SequenceBox()
        let customCoordinator = CleanupCoordinator(
            engine: engine,
            journal: journal,
            settings: settings,
            trashManager: trashManager,
            itemManager: itemManager,
            trashDirectoryURL: trashDirectory,
            availableCapacityProvider: { capacityBox.next() }
        )
        coordinator = customCoordinator

        customCoordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let installerLabel = CleanupCategory.installerPackages.localizedTitle
        itemManager.appendFileItem(
            path: bigFile.path,
            sizeBytes: 1024,
            modificationDate: Date(),
            isDirectory: false,
            category: installerLabel,
            parentName: installerLabel,
            isSelected: true
        )

        customCoordinator.executeCleanup(options: CleanupOptions(targetCategories: []))
        try await waitForState(.completed)

        XCTAssertTrue(customCoordinator.usedPermanentDeletion)
        XCTAssertEqual(customCoordinator.apfsDeltaBytes, 500_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bigFile.path))

        let tx = try await journal.loadAll()
        let op = tx.last?.operations.first
        XCTAssertEqual(op?.categoryCode, CleanupCategory.installerPackages.rawValue)
        XCTAssertEqual(op?.deletionMode, OperationRecord.DeletionMode.permanent.rawValue)
        XCTAssertEqual(op?.skipped, 0)
        XCTAssertEqual(op?.failed, 0)
    }

    func testExecuteCleanup_defaultTrashMode_leavesAPFSDeltaNilAndLogsTrashMode() async throws {
        let savedBypass = settings.bypassTrashOnUninstall
        defer { settings.bypassTrashOnUninstall = savedBypass }
        settings.emptyTrashDuringCleanup = false
        settings.bypassTrashOnUninstall = false

        let downloads = fileSystemContext.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let bigFile = downloads.appendingPathComponent("TrashInstaller.dmg")
        try Data(repeating: 0xDD, count: 1024).write(to: bigFile)

        coordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let installerLabel = CleanupCategory.installerPackages.localizedTitle
        itemManager.appendFileItem(
            path: bigFile.path,
            sizeBytes: 1024,
            modificationDate: Date(),
            isDirectory: false,
            category: installerLabel,
            parentName: installerLabel,
            isSelected: true
        )

        coordinator.executeCleanup(options: CleanupOptions(targetCategories: []))
        try await waitForState(.completed)

        XCTAssertFalse(coordinator.usedPermanentDeletion)
        XCTAssertNil(coordinator.apfsDeltaBytes)
        let tx = try await journal.loadAll()
        let op = tx.last?.operations.first
        XCTAssertEqual(op?.categoryCode, CleanupCategory.installerPackages.rawValue)
        XCTAssertEqual(op?.deletionMode, OperationRecord.DeletionMode.trash.rawValue)
        XCTAssertEqual(op?.failed, 0)
    }

    func testExecuteCleanup_tracksCleanedFontCacheAndResets() async throws {
        let mockRunner = MockCommandRunner()
        let customEngine = CleanupEngine(
            commandRunner: mockRunner,
            safetyManager: SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext),
            fileSystemContext: fileSystemContext
        )
        let customCoordinator = CleanupCoordinator(
            engine: customEngine,
            journal: journal,
            settings: settings,
            trashManager: trashManager,
            itemManager: itemManager,
            trashDirectoryURL: trashDirectory
        )
        coordinator = customCoordinator

        customCoordinator.startScan(options: CleanupOptions(targetCategories: []))
        try await waitForState(.preview)

        let fontLabel = CleanupCategory.fontCache.localizedTitle
        itemManager.appendFileItem(
            path: "command://font/cache-clear",
            sizeBytes: 0,
            modificationDate: nil,
            isDirectory: false,
            category: fontLabel,
            parentName: fontLabel,
            isSelected: true,
            isCommandBacked: true
        )

        customCoordinator.executeCleanup(options: CleanupOptions(targetCategories: [.fontCache], cleanFontCache: true))
        try await waitForState(.completed)

        XCTAssertTrue(customCoordinator.cleanedFontCache)
        customCoordinator.reset()
        XCTAssertFalse(customCoordinator.cleanedFontCache)
    }
}
