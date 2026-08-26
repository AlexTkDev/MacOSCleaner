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
        "uninstaller_show_in_finder"
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
