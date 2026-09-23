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
        "duplicate_no_selection",
        "cleanup_base_section_title",
        "cleanup_base_system_cache",
        "cleanup_base_app_logs",
        "cleanup_base_browser_cache",
        "cleanup_base_trash",
        "cleanup_badge_password"
    ]

    func testAllSupportedLanguagesContainRequiredLeftoverKeys() {
        let languages = AppLanguage.allCases
        XCTAssertEqual(languages.count, 14, "Should have 14 supported languages")

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
            "uk.lproj", "zh-Hans.lproj", "ar.lproj", "zh-Hant.lproj",
            "ko.lproj", "pl.lproj"
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

    func testEveryLprojMatchesEnglishKeysAndPlaceholders() throws {
        let fileManager = FileManager.default
        let resourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let locales = [
            "en", "ru", "de", "es", "fr", "it", "ja", "pt-BR", "uk", "zh-Hans",
            "ar", "zh-Hant", "ko", "pl"
        ]
        let englishURL = resourcesDir.appendingPathComponent("en.lproj/Localizable.strings")
        let english = try localizationMap(at: englishURL)
        XCTAssertFalse(english.isEmpty)

        for locale in locales {
            let url = resourcesDir.appendingPathComponent("\(locale).lproj/Localizable.strings")
            XCTAssertTrue(fileManager.fileExists(atPath: url.path), "Missing \(locale).lproj")
            let map = try localizationMap(at: url)
            let missing = Set(english.keys).subtracting(map.keys)
            let extra = Set(map.keys).subtracting(english.keys)
            XCTAssertTrue(missing.isEmpty, "\(locale) missing keys: \(missing.sorted())")
            XCTAssertTrue(extra.isEmpty, "\(locale) extra keys: \(extra.sorted())")
            for (key, source) in english {
                let translated = map[key] ?? ""
                XCTAssertFalse(translated.isEmpty, "\(locale) empty value for \(key)")
                XCTAssertEqual(
                    placeholders(in: translated),
                    placeholders(in: source),
                    "\(locale) placeholder mismatch for \(key)"
                )
            }
        }
    }

    private func localizationMap(at url: URL) throws -> [String: String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var map: [String: String] = [:]
        let pattern = #/^"(?<key>(?:\\.|[^"\\])*)"\s*=\s*"(?<value>(?:\\.|[^"\\])*)";/#
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.wholeMatch(of: pattern) else { continue }
            map[String(match.key)] = String(match.value)
        }
        return map
    }

    /// Compares specifier kinds, ignoring argument indexes so `%1$@` matches `%@`.
    private func placeholders(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"%%|%(?:\d+\$)?(?:\.\d+)?(?:ll|l)?[df@]"#
        ) else {
            return []
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let span = Range(match.range, in: value) else { return nil }
            let token = String(value[span])
            if token == "%%" { return token }
            return token.replacing(/(\d+)\$/, with: "")
        }.sorted()
    }
}
