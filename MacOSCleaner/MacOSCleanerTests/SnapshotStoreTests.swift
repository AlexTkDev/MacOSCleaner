import XCTest
@testable import MacOSCleaner

final class SnapshotStoreTests: XCTestCase {
    var testRoot: URL!
    var store: SnapshotStore!

    override func setUp() {
        super.setUp()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotStoreTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        store = SnapshotStore(storageURL: testRoot)
    }

    override func tearDown() {
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        super.tearDown()
    }

    func testSaveAndLoad() async throws {
        let snapshot = UninstallSnapshot(
            appName: "TestApp",
            bundleID: "com.test.app",
            appVersion: "1.0",
            appBundlePath: "/Applications/TestApp.app",
            deletedPaths: [
                "/Applications/TestApp.app",
                "~/Library/Application Support/TestApp",
                "~/Library/Caches/com.test.app",
            ],
            bypassTrash: false
        )

        try await store.save(snapshot: snapshot)

        let loaded = try await store.load(id: snapshot.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.appName, "TestApp")
        XCTAssertEqual(loaded?.bundleID, "com.test.app")
        XCTAssertEqual(loaded?.appVersion, "1.0")
        XCTAssertEqual(loaded?.deletedPaths.count, 3)
        XCTAssertFalse(loaded?.bypassTrash ?? true)
    }

    func testList_returnsSnapshotsInReverseChronologicalOrder() async throws {
        let earlier = UninstallSnapshot(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-3600),
            appName: "OldApp",
            bundleID: "com.old.app",
            appVersion: nil,
            appBundlePath: "/Applications/OldApp.app",
            deletedPaths: ["/Applications/OldApp.app"],
            bypassTrash: false
        )
        let later = UninstallSnapshot(
            id: UUID(),
            timestamp: Date(),
            appName: "NewApp",
            bundleID: "com.new.app",
            appVersion: "2.0",
            appBundlePath: "/Applications/NewApp.app",
            deletedPaths: ["/Applications/NewApp.app"],
            bypassTrash: true
        )

        try await store.save(snapshot: earlier)
        try await store.save(snapshot: later)

        let list = try await store.list()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].appName, "NewApp")
        XCTAssertEqual(list[1].appName, "OldApp")
    }

    func testDelete_removesSnapshot() async throws {
        let snapshot = UninstallSnapshot(
            appName: "TestApp",
            bundleID: "com.test.app",
            appVersion: nil,
            appBundlePath: "/Applications/TestApp.app",
            deletedPaths: ["/Applications/TestApp.app"],
            bypassTrash: false
        )

        try await store.save(snapshot: snapshot)
        var count = try await store.snapshotCount()
        XCTAssertEqual(count, 1)

        try await store.delete(id: snapshot.id)
        count = try await store.snapshotCount()
        XCTAssertEqual(count, 0)
        let loaded = try await store.load(id: snapshot.id)
        XCTAssertNil(loaded)
    }

    func testLoad_nonexistentId_returnsNil() async throws {
        let loaded = try await store.load(id: UUID())
        XCTAssertNil(loaded)
    }

    func testList_emptyStore_returnsEmptyArray() async throws {
        let list = try await store.list()
        XCTAssertTrue(list.isEmpty)
    }
}
