import XCTest
@testable import MacOSCleaner

final class LocalizationCompletenessTests: XCTestCase {

    override func invokeTest() {
        LanguageManager.testingLock.lock()
        defer { LanguageManager.testingLock.unlock() }
        super.invokeTest()
    }

    override func setUp() {
        super.setUp()
        LanguageManager.shared.setLanguage(.english)
    }

    override func tearDown() {
        LanguageManager.shared.setLanguage(.english)
        super.tearDown()
    }

    private let requiredLeftoverKeys = [
        "uninstaller_tab_apps",
        "uninstaller_tab_leftovers",
        "uninstaller_leftovers_hero_title",
        "uninstaller_leftovers_hero_subtitle",
        "uninstaller_start_leftover_scan",
        "uninstaller_scanning_leftovers",
        "uninstaller_no_leftovers_title",
        "uninstaller_no_leftovers_subtitle",
        "uninstaller_leftovers_found_count",
        "uninstaller_filter_all",
        "uninstaller_clean_selected_leftovers",
        "uninstaller_confirm_trash_leftovers_title",
        "uninstaller_confirm_trash_leftovers_message",
        "uninstaller_post_leftovers_title",
        "uninstaller_post_leftovers_subtitle",
        "uninstaller_evidence_card_title",
        "uninstaller_evidence_why_flagged",
        "uninstaller_leftovers_cleaned_notification",
        "uninstaller_show_in_finder",
        "menu_donate",
        "about_donate",
        "category.project_build_artifacts",
        "settings_project_artifacts_age",
        "settings_project_artifacts_age_sub",
        "settings_days_count",
        "disk_analyzer_items_count",
        "disk_analyzer_quick_look",
        "disk_analyzer_open_folder",
        "cleanup_option_font_cache",
        "cleanup_option_font_cache_sub",
        "cleanup_font_cache_confirm_title",
        "cleanup_font_cache_confirm_message",
        "cleanup_font_cache_confirm_action",
        "dashboard_view_all_history",
        "history_window_title",
        "history_search_placeholder",
        "history_sort_date",
        "history_sort_size",
        "history_trigger_manual",
        "history_trigger_automatic",
        "history_empty_state",
        "history_category_general",
        "history_category_media",
        "history_category_caches",
        "history_category_dev",
        "settings_ai_status_preparing",
        "settings_ai_status_unsupported_language",
        "settings_ai_hint_unsupported_language",
        "settings_ai_hint_preparing",
        "settings_ai_hint_not_enabled",
        "settings_ai_hint_unsupported_device",
        "settings_ai_open_system_settings",
        "settings_ai_refresh_status",
        "duplicate_badge_original",
        "duplicate_badge_duplicate",
        "duplicate_copies_count",
        "duplicate_no_selection"
    ]

    func testAllSupportedLanguagesContainRequiredLeftoverKeys() {
        let languages = AppLanguage.allCases
        XCTAssertEqual(languages.count, 10, "Should have 10 supported languages")

        for lang in languages {
            LanguageManager.shared.setLanguage(lang)
            for key in requiredLeftoverKeys {
                let localized = key.localized
                XCTAssertFalse(
                    localized.isEmpty,
                    "Key '\(key)' is empty for language '\(lang.rawValue)'"
                )
                XCTAssertNotEqual(
                    localized,
                    key,
                    "Key '\(key)' is missing translation in language '\(lang.rawValue)'"
                )
            }
        }
    }

    func testAllLprojFilesContainRequiredKeysDirectly() throws {
        let fileManager = FileManager.default
        let expectedLprojs = [
            "en.lproj", "ru.lproj", "de.lproj", "es.lproj",
            "fr.lproj", "it.lproj", "ja.lproj", "pt-BR.lproj",
            "uk.lproj", "zh-Hans.lproj"
        ]

        // Find Resources path from source tree or bundle
        let possiblePaths = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources"),
            Bundle.main.resourceURL ?? URL(fileURLWithPath: "/nonexistent")
        ]

        guard let resourcesDir = possiblePaths.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return // Skip file system check if resources dir not located
        }

        for lprojName in expectedLprojs {
            let stringsFileURL = resourcesDir.appendingPathComponent(lprojName).appendingPathComponent("Localizable.strings")
            guard fileManager.fileExists(atPath: stringsFileURL.path) else {
                XCTFail("Missing Localizable.strings file at \(stringsFileURL.path)")
                continue
            }

            let content = try String(contentsOf: stringsFileURL, encoding: .utf8)
            for key in requiredLeftoverKeys {
                let pattern = "\"\(key)\""
                XCTAssertTrue(
                    content.contains(pattern),
                    "File \(lprojName)/Localizable.strings is missing key \(key)"
                )
            }
        }
    }
}
