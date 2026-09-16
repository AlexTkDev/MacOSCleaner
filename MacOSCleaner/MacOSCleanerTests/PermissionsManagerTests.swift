import XCTest
@testable import MacOSCleaner

final class PermissionsManagerTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private let suiteName = "com.macoscleaner.test.permissions"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    func testInitialState_whenNotGranted_showsGuidanceOnDemand() {
        let manager = PermissionsManager(userDefaults: testDefaults, fdaCheck: { false })
        
        XCTAssertFalse(manager.hasFullDiskAccess)
        XCTAssertFalse(manager.fdaEverGranted)
        XCTAssertFalse(manager.showGuidance)

        manager.showGuidanceIfNeeded()
        XCTAssertTrue(manager.showGuidance, "If FDA is not obtained, guidance must be shown continuously on launch")
    }

    func testInitialState_whenGrantedLive_remembersAndSuppressesGuidance() {
        let manager = PermissionsManager(userDefaults: testDefaults, fdaCheck: { true })
        
        XCTAssertTrue(manager.hasFullDiskAccess)
        XCTAssertTrue(manager.fdaEverGranted)
        XCTAssertTrue(testDefaults.bool(forKey: "com.macoscleaner.fdaGranted"))

        manager.showGuidanceIfNeeded()
        XCTAssertFalse(manager.showGuidance, "If FDA is granted, guidance must NOT be shown")
    }

    func testSubsequentLaunch_whenPreviouslyGranted_remembersAndNeverPromptsAgain() {
        testDefaults.set(true, forKey: "com.macoscleaner.fdaGranted")

        // Even if live check returns false during app init, remembered grant must be preserved
        let manager = PermissionsManager(userDefaults: testDefaults, fdaCheck: { false })
        
        XCTAssertTrue(manager.hasFullDiskAccess)
        XCTAssertTrue(manager.fdaEverGranted)

        manager.showGuidanceIfNeeded()
        XCTAssertFalse(manager.showGuidance, "Subsequent launch must remember granted permission and not prompt again")
    }

    func testGuidanceDismissTemporarily_promptsAgainOnNextLaunchUntilGranted() {
        var manager = PermissionsManager(userDefaults: testDefaults, fdaCheck: { false })
        manager.showGuidanceIfNeeded()
        XCTAssertTrue(manager.showGuidance)

        // User temporarily dismisses ("Пропустить пока")
        manager.dismissGuidanceTemporarily()
        XCTAssertFalse(manager.showGuidance)

        // Next launch without grant: must prompt again
        manager = PermissionsManager(userDefaults: testDefaults, fdaCheck: { false })
        manager.showGuidanceIfNeeded()
        XCTAssertTrue(manager.showGuidance, "If permission not granted, app should keep asking on launch")
    }

    private final class MockFDABox: @unchecked Sendable {
        var isGranted: Bool = false
    }

    func testRefresh_whenUserGrantsPermission_updatesStateAndDismissesGuidance() {
        let box = MockFDABox()
        let manager = PermissionsManager(userDefaults: testDefaults, fdaCheck: { box.isGranted })
        manager.showGuidanceIfNeeded()
        XCTAssertTrue(manager.showGuidance)

        // User enables FDA in System Settings and returns to app
        box.isGranted = true
        manager.refresh()

        XCTAssertTrue(manager.hasFullDiskAccess)
        XCTAssertTrue(manager.fdaEverGranted)
        XCTAssertFalse(manager.showGuidance, "Guidance sheet must automatically dismiss once FDA is granted")
        XCTAssertTrue(testDefaults.bool(forKey: "com.macoscleaner.fdaGranted"))

        // Next check should never show guidance
        manager.showGuidanceIfNeeded()
        XCTAssertFalse(manager.showGuidance)
    }

    func testRequestGuidanceAgain_resetsAndShowsGuidance() {
        testDefaults.set(true, forKey: "com.macoscleaner.guidanceDismissed")
        testDefaults.set(true, forKey: "com.macoscleaner.fdaGranted")

        let manager = PermissionsManager(userDefaults: testDefaults, fdaCheck: { false })
        XCTAssertFalse(manager.showGuidance)

        manager.requestGuidanceAgain()
        XCTAssertTrue(manager.showGuidance)
        XCTAssertFalse(manager.guidanceDismissed)
    }
}
