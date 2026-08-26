import XCTest
@testable import MacOSCleaner

@MainActor
final class AppSettingsTests: XCTestCase {
    override func invokeTest() {
        LanguageManager.testingLock.lock()
        defer { LanguageManager.testingLock.unlock() }
        super.invokeTest()
    }

    override func setUp() async throws {
        let keysToReset = [
            "settings_language", "settings_theme", "settings_showNotifications",
            "settings_showTooltips", "settings_autoScanOnStartup",
            "settings_emptyTrashDuringCleanup", "settings_bypassTrashOnUninstall",
            "settings_showRelatedFiles", "settings_emptyTrashImmediately",
            "settings_enableAI", "settings_isDebugMode"
        ]
        keysToReset.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() async throws {
        let keysToReset = [
            "settings_language", "settings_theme", "settings_showNotifications",
            "settings_showTooltips", "settings_autoScanOnStartup",
            "settings_emptyTrashDuringCleanup", "settings_bypassTrashOnUninstall",
            "settings_showRelatedFiles", "settings_emptyTrashImmediately",
            "settings_enableAI", "settings_isDebugMode"
        ]
        keysToReset.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - Defaults

    func testDefaultValues() {
        let settings = AppSettings()
        XCTAssertEqual(settings.language, .english)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertFalse(settings.showNotifications)
        XCTAssertTrue(settings.showTooltips)
        XCTAssertFalse(settings.autoScanOnStartup)
        XCTAssertFalse(settings.emptyTrashDuringCleanup)
        XCTAssertFalse(settings.bypassTrashOnUninstall)
        XCTAssertTrue(settings.showRelatedFiles)
        XCTAssertFalse(settings.emptyTrashImmediately)
        XCTAssertTrue(settings.enableAI)
        XCTAssertFalse(settings.isDebugMode)
        XCTAssertEqual(settings.projectArtifactsOlderThanDays, 60)
    }

    func testProjectArtifactsAgePersisted() {
        let settings = AppSettings()
        settings.projectArtifactsOlderThanDays = 90
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "settings_projectArtifactsOlderThanDays"), 90)
    }

    func testLanguagePersisted() {
        let settings = AppSettings()
        settings.language = .russian
        let persisted = UserDefaults.standard.string(forKey: "settings_language")
        XCTAssertEqual(persisted, AppLanguage.russian.rawValue)
    }

    func testThemePersisted() {
        let settings = AppSettings()
        settings.theme = .dark
        let persisted = UserDefaults.standard.string(forKey: "settings_theme")
        XCTAssertEqual(persisted, AppTheme.dark.rawValue)
    }

    func testBoolFlagsPersisted() {
        let settings = AppSettings()
        settings.autoScanOnStartup = true
        settings.emptyTrashDuringCleanup = true
        settings.bypassTrashOnUninstall = true
        settings.showRelatedFiles = false
        settings.emptyTrashImmediately = true
        settings.enableAI = false
        settings.isDebugMode = true
 
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "settings_autoScanOnStartup"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "settings_emptyTrashDuringCleanup"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "settings_bypassTrashOnUninstall"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "settings_showRelatedFiles"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "settings_emptyTrashImmediately"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "settings_enableAI"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "settings_isDebugMode"))
    }

    // MARK: - Reset

    func testResetAllRestoresDefaults() {
        let settings = AppSettings()
        settings.language = .russian
        settings.theme = .dark
        settings.showNotifications = false
        settings.showTooltips = false
        settings.autoScanOnStartup = true
        settings.emptyTrashDuringCleanup = true
        settings.bypassTrashOnUninstall = true
        settings.showRelatedFiles = false
        settings.emptyTrashImmediately = true
        settings.enableAI = false
        settings.isDebugMode = true
        settings.projectArtifactsOlderThanDays = 180
 
        settings.resetAll()
 
        XCTAssertEqual(settings.language, .english)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertFalse(settings.showNotifications)
        XCTAssertTrue(settings.showTooltips)
        XCTAssertFalse(settings.autoScanOnStartup)
        XCTAssertFalse(settings.emptyTrashDuringCleanup)
        XCTAssertFalse(settings.bypassTrashOnUninstall)
        XCTAssertTrue(settings.showRelatedFiles)
        XCTAssertFalse(settings.emptyTrashImmediately)
        XCTAssertTrue(settings.enableAI)
        XCTAssertFalse(settings.isDebugMode)
        XCTAssertEqual(settings.projectArtifactsOlderThanDays, 60)
    }
}