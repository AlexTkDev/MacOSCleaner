import SwiftUI
import XCTest
@testable import MacOSCleaner

final class LanguageManagerTests: XCTestCase {

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
    
    func testLocalizationDefaultEnglish() {
        XCTAssertEqual("welcome_msg".localized, "Welcome back!")
    }

    func testThemeKeysMatchSelectedLanguage() {
        let cases: [(AppLanguage, String, String, String)] = [
            (.english, "System", "Light", "Dark"),
            (.russian, "Системная", "Светлая", "Тёмная"),
            (.french, "Système", "Clair", "Sombre"),
            (.german, "System", "Hell", "Dunkel"),
            (.italian, "Di sistema", "Chiaro", "Scuro"),
            (.portugueseBrazil, "Sistema", "Claro", "Escuro"),
            (.arabic, "النظام", "فاتح", "داكن"),
            (.chineseTraditional, "跟隨系統", "淺色", "深色"),
            (.korean, "시스템", "라이트", "다크"),
            (.polish, "Systemowy", "Jasny", "Ciemny"),
        ]
        for (lang, system, light, dark) in cases {
            LanguageManager.shared.setLanguage(lang)
            XCTAssertEqual("theme_system".localized, system, "theme_system for \(lang)")
            XCTAssertEqual("theme_light".localized, light, "theme_light for \(lang)")
            XCTAssertEqual("theme_dark".localized, dark, "theme_dark for \(lang)")
        }
    }

    func testLanguageDisplayNamesMatchSelectedLanguage() {
        LanguageManager.shared.setLanguage(.english)
        XCTAssertEqual("language.english".localized, "English")
        XCTAssertEqual("language.russian".localized, "Russian")

        LanguageManager.shared.setLanguage(.french)
        XCTAssertEqual("language.english".localized, "Anglais")
        XCTAssertEqual("language.french".localized, "Français")

        LanguageManager.shared.setLanguage(.russian)
        XCTAssertEqual("language.english".localized, "Английский")
        XCTAssertEqual("language.russian".localized, "Русский")

        LanguageManager.shared.setLanguage(.arabic)
        XCTAssertEqual("language.arabic".localized, "العربية")

        LanguageManager.shared.setLanguage(.chineseTraditional)
        XCTAssertEqual("language.chinese_traditional".localized, "繁體中文")

        LanguageManager.shared.setLanguage(.korean)
        XCTAssertEqual("language.korean".localized, "한국어")

        LanguageManager.shared.setLanguage(.polish)
        XCTAssertEqual("language.polish".localized, "Polski")
    }

    func testNewLanguageLocalesAndLayoutDirection() {
        XCTAssertEqual(AppLanguage.arabic.locale.language.languageCode?.identifier, "ar")
        XCTAssertEqual(AppLanguage.arabic.locale.region?.identifier, "SA")
        XCTAssertEqual(AppLanguage.arabic.layoutDirection, .rightToLeft)

        XCTAssertEqual(AppLanguage.chineseTraditional.locale.language.script?.identifier, "Hant")
        XCTAssertEqual(AppLanguage.chineseTraditional.locale.region?.identifier, "TW")
        XCTAssertEqual(AppLanguage.korean.locale.language.languageCode?.identifier, "ko")
        XCTAssertEqual(AppLanguage.korean.locale.region?.identifier, "KR")
        XCTAssertEqual(AppLanguage.polish.locale.language.languageCode?.identifier, "pl")
        XCTAssertEqual(AppLanguage.polish.locale.region?.identifier, "PL")

        for language in AppLanguage.allCases where language != .arabic {
            XCTAssertEqual(language.layoutDirection, .leftToRight, language.rawValue)
        }
    }

    func testMissingKeyFallsBackToEnglishNotSystemLocale() {
        LanguageManager.shared.setLanguage(.french)
        // Unknown key must not leak another locale's translation.
        let value = "totally_missing_key_xyz".localized
        XCTAssertEqual(value, "totally_missing_key_xyz")
    }
    
    func testLocalizationSwitchToRussian() {
        LanguageManager.shared.setLanguage(.russian)
        XCTAssertEqual("welcome_msg".localized, "С возвращением!")
    }
    
    func testLocalizationSwitchToUkrainian() {
        LanguageManager.shared.setLanguage(.ukrainian)
        XCTAssertEqual("welcome_msg".localized, "З поверненням!")
    }
    
    func testLocalizationSwitchToSpanish() {
        LanguageManager.shared.setLanguage(.spanish)
        XCTAssertEqual("welcome_msg".localized, "¡Bienvenido de nuevo!")
    }

    func testLocalizationSwitchToArabic() {
        LanguageManager.shared.setLanguage(.arabic)
        XCTAssertEqual("welcome_msg".localized, "مرحبًا بعودتك!")
    }

    func testLocalizationSwitchToChineseTraditional() {
        LanguageManager.shared.setLanguage(.chineseTraditional)
        XCTAssertEqual("welcome_msg".localized, "歡迎回來！")
    }

    func testLocalizationSwitchToKorean() {
        LanguageManager.shared.setLanguage(.korean)
        XCTAssertEqual("welcome_msg".localized, "다시 오신 것을 환영합니다!")
    }

    func testLocalizationSwitchToPolish() {
        LanguageManager.shared.setLanguage(.polish)
        XCTAssertEqual("welcome_msg".localized, "Witaj ponownie!")
    }
    
    func testLocalizationWithArgs() {
        let template = "Hello %@"
        let formatted = template.localizedWithArgs("Alex")
        XCTAssertEqual(formatted, "Hello Alex")
    }

    func testFormattedByteCountRespectsLanguage() {
        let gigabytes: Int64 = 17 * 1024 * 1024 * 1024
        LanguageManager.shared.setLanguage(.english)
        XCTAssertTrue(gigabytes.formattedByteCount().contains("GB"))

        LanguageManager.shared.setLanguage(.russian)
        XCTAssertTrue(gigabytes.formattedByteCount().contains("ГБ"))

        LanguageManager.shared.setLanguage(.french)
        XCTAssertTrue(gigabytes.formattedByteCount().contains("Go"))

        LanguageManager.shared.setLanguage(.english)
    }
}
