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
    
    func testLocalizationWithArgs() {
        let template = "Hello %@"
        let formatted = template.localizedWithArgs("Alex")
        XCTAssertEqual(formatted, "Hello Alex")
    }
}
