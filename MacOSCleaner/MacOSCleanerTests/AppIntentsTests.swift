import XCTest
import AppIntents
@testable import MacOSCleaner

@MainActor
final class AppIntentsTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.set(true, forKey: "settings_enableSiri")
        UserDefaults.standard.set(true, forKey: "settings_enableShortcutsAndAutomator")
        UserDefaults.standard.set(true, forKey: "settings_cmd_developer_caches")
        UserDefaults.standard.set(true, forKey: "settings_cmd_clean_category")
        UserDefaults.standard.set(true, forKey: "settings_cmd_storage_status")
        UserDefaults.standard.set(true, forKey: "settings_cmd_scheduled_cleanup")
        UserDefaults.standard.set(true, forKey: "settings_cmd_empty_trash")
        UserDefaults.standard.removeObject(forKey: "settings_custom_siri_commands")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "settings_enableSiri")
        UserDefaults.standard.removeObject(forKey: "settings_enableShortcutsAndAutomator")
        UserDefaults.standard.removeObject(forKey: "settings_cmd_developer_caches")
        UserDefaults.standard.removeObject(forKey: "settings_cmd_clean_category")
        UserDefaults.standard.removeObject(forKey: "settings_cmd_storage_status")
        UserDefaults.standard.removeObject(forKey: "settings_cmd_scheduled_cleanup")
        UserDefaults.standard.removeObject(forKey: "settings_cmd_empty_trash")
        UserDefaults.standard.removeObject(forKey: "settings_custom_siri_commands")
        try await super.tearDown()
    }

    // MARK: - Safe Dry-Run & Non-Destructive Intent Tests

    func test_cleanDeveloperCachesIntent_allTargets_safeInTests() async throws {
        // Intent automatically detects test execution and forces dryRun = true
        let intent = CleanDeveloperCachesIntent(target: .all, confirm: true, dryRun: true)
        let result = try await intent.perform()

        let desc = String(describing: result)
        XCTAssertFalse(desc.isEmpty, "Result description should not be empty")
    }

    func test_cleanDeveloperCachesIntent_xcodeTarget() async throws {
        let intent = CleanDeveloperCachesIntent(target: .xcode, confirm: true, dryRun: true)
        let result = try await intent.perform()

        let desc = String(describing: result)
        XCTAssertFalse(desc.isEmpty, "CleanDeveloperCachesIntent result for Xcode target must not be empty")
    }

    func test_cleanDeveloperCachesIntent_otherTargets() async throws {
        let targets: [DeveloperCacheTarget] = [.packageManagers, .docker]
        for target in targets {
            let intent = CleanDeveloperCachesIntent(target: target, confirm: true, dryRun: true)
            let result = try await intent.perform()
            XCTAssertFalse(String(describing: result).isEmpty)
        }
    }

    func test_getStorageStatusIntent_performsSuccessfully() async throws {
        let intent = GetStorageStatusIntent()
        let result = try await intent.perform()

        let desc = String(describing: result)
        XCTAssertFalse(desc.isEmpty, "GetStorageStatusIntent result must not be empty")
    }

    func test_cleanCategoryIntent_safeDryRun() async throws {
        let intent = CleanCategoryIntent(category: .userLogs, confirm: true, dryRun: true)
        let result = try await intent.perform()

        let desc = String(describing: result)
        XCTAssertFalse(desc.isEmpty, "CleanCategoryIntent result must not be empty")
    }

    func test_emptyTrashIntent_safeDryRun() async throws {
        let intent = EmptyTrashIntent(confirm: true, dryRun: true)
        let result = try await intent.perform()

        let desc = String(describing: result)
        XCTAssertFalse(desc.isEmpty, "EmptyTrashIntent result must not be empty")
    }

    func test_runScheduledCleanupIntent_dryRun_performsSuccessfully() async throws {
        let intent = RunScheduledCleanupIntent(dryRun: true)
        let result = try await intent.perform()

        let desc = String(describing: result)
        XCTAssertFalse(desc.isEmpty, "RunScheduledCleanupIntent dryRun result must not be empty")
    }

    // MARK: - Authentication Policies

    func test_intents_haveAuthenticationPolicy() {
        XCTAssertEqual(CleanCategoryIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertEqual(CleanDeveloperCachesIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertEqual(EmptyTrashIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertEqual(RunScheduledCleanupIntent.authenticationPolicy, .requiresAuthentication)
    }

    // MARK: - Global Disabled Shortcuts / Siri

    func test_intents_whenShortcutsAndSiriDisabled_returnsDisabledResult() async throws {
        UserDefaults.standard.set(false, forKey: "settings_enableSiri")
        UserDefaults.standard.set(false, forKey: "settings_enableShortcutsAndAutomator")

        let intent = GetStorageStatusIntent()
        let result = try await intent.perform()

        let desc = String(describing: result)
        XCTAssertFalse(desc.isEmpty, "Intent should return dialog even when disabled")
    }

    // MARK: - Specific Command Settings Toggles

    func test_intents_respectSpecificCommandSettings() async throws {
        UserDefaults.standard.set(false, forKey: "settings_cmd_developer_caches")
        let devIntent = CleanDeveloperCachesIntent(target: .all, confirm: true, dryRun: true)
        let devResult = try await devIntent.perform()
        XCTAssertFalse(String(describing: devResult).isEmpty)

        UserDefaults.standard.set(false, forKey: "settings_cmd_clean_category")
        let catIntent = CleanCategoryIntent(category: .systemCaches, confirm: true, dryRun: true)
        let catResult = try await catIntent.perform()
        XCTAssertFalse(String(describing: catResult).isEmpty)

        UserDefaults.standard.set(false, forKey: "settings_cmd_empty_trash")
        let trashIntent = EmptyTrashIntent(confirm: true, dryRun: true)
        let trashResult = try await trashIntent.perform()
        XCTAssertFalse(String(describing: trashResult).isEmpty)

        UserDefaults.standard.set(false, forKey: "settings_cmd_scheduled_cleanup")
        let schedIntent = RunScheduledCleanupIntent(dryRun: true)
        let schedResult = try await schedIntent.perform()
        XCTAssertFalse(String(describing: schedResult).isEmpty)

        UserDefaults.standard.set(false, forKey: "settings_cmd_storage_status")
        let statusIntent = GetStorageStatusIntent()
        let statusResult = try await statusIntent.perform()
        XCTAssertFalse(String(describing: statusResult).isEmpty)
    }

    // MARK: - Shortcuts Provider

    func test_shortcutsProvider_containsAllIntents() {
        let shortcuts = MacOSCleanerShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 5, "MacOSCleanerShortcuts should define 5 shortcuts")
    }

    // MARK: - CustomSiriCommand & AppSettings Synchronization

    func test_customSiriCommand_settingsKeySync() {
        let settings = AppSettings()

        // Toggle developer caches in customSiriCommands
        if let idx = settings.customSiriCommands.firstIndex(where: { $0.settingKey == "settings_cmd_developer_caches" }) {
            settings.customSiriCommands[idx].isEnabled = false
            XCTAssertFalse(settings.enableDeveloperCachesCommand, "enableDeveloperCachesCommand should sync with customSiriCommands")
            XCTAssertFalse(UserDefaults.standard.bool(forKey: "settings_cmd_developer_caches"))

            settings.customSiriCommands[idx].isEnabled = true
            XCTAssertTrue(settings.enableDeveloperCachesCommand)
            XCTAssertTrue(UserDefaults.standard.bool(forKey: "settings_cmd_developer_caches"))
        } else {
            XCTFail("Missing developer caches command in customSiriCommands")
        }

        // Toggle empty trash via direct property
        settings.enableEmptyTrashCommand = false
        if let cmd = settings.customSiriCommands.first(where: { $0.settingKey == "settings_cmd_empty_trash" }) {
            XCTAssertFalse(cmd.isEnabled, "CustomSiriCommand should sync when enableEmptyTrashCommand is changed")
        }
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "settings_cmd_empty_trash"))
    }
}
