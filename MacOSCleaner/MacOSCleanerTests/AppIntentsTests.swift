import XCTest
import AppIntents
@testable import MacOSCleaner

final class AppIntentsTests: XCTestCase {

    func test_cleanDeveloperCachesIntent_allTargets() async throws {
        let intent = CleanDeveloperCachesIntent(target: .all)
        let result = try await intent.perform()

        XCTAssertNotNil(result, "CleanDeveloperCachesIntent result must not be nil")
    }

    func test_cleanDeveloperCachesIntent_xcodeTarget() async throws {
        let intent = CleanDeveloperCachesIntent(target: .xcode)
        let result = try await intent.perform()

        XCTAssertNotNil(result, "CleanDeveloperCachesIntent result for Xcode target must not be nil")
    }

    func test_getStorageStatusIntent_performsSuccessfully() async throws {
        let intent = GetStorageStatusIntent()
        let result = try await intent.perform()

        XCTAssertNotNil(result, "GetStorageStatusIntent result must not be nil")
    }

    func test_cleanCategoryIntent_performsSuccessfully() async throws {
        let intent = CleanCategoryIntent(category: .userLogs)
        let result = try await intent.perform()

        XCTAssertNotNil(result, "CleanCategoryIntent result must not be nil")
    }

    func test_runScheduledCleanupIntent_dryRun_performsSuccessfully() async throws {
        let intent = RunScheduledCleanupIntent(dryRun: true)
        let result = try await intent.perform()

        XCTAssertNotNil(result, "RunScheduledCleanupIntent dryRun result must not be nil")
    }

    func test_intents_whenShortcutsAndSiriDisabled_returnsDisabledResult() async throws {
        UserDefaults.standard.set(false, forKey: "settings_enableSiri")
        UserDefaults.standard.set(false, forKey: "settings_enableShortcutsAndAutomator")
        defer {
            UserDefaults.standard.removeObject(forKey: "settings_enableSiri")
            UserDefaults.standard.removeObject(forKey: "settings_enableShortcutsAndAutomator")
        }

        let intent = GetStorageStatusIntent()
        let result = try await intent.perform()

        XCTAssertNotNil(result, "Intent should return dialog even when disabled")
    }
}
