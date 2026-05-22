import XCTest
@testable import MacOSCleaner

final class LanguageManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Сбросим язык по умолчанию на английский перед каждым тестом
        LanguageManager.shared.setLanguage(.english)
    }
    
    func testLocalizationDefaultEnglish() {
        XCTAssertEqual("welcome_msg".localized, "Welcome back!")
    }
    
    func testLocalizationSwitchToRussian() {
        LanguageManager.shared.setLanguage(.russian)
        XCTAssertEqual("welcome_msg".localized, "С возвращением!")
    }
    
    func testLocalizationSwitchToUkrainian() {
        LanguageManager.shared.setLanguage(.ukrainian)
        XCTAssertEqual("welcome_msg".localized, "З поверненням!")
    }
    
    func testLocalizationWithArgs() {
        // Мы не добавляли ключей с аргументами, но можем проверить форматирование
        let template = "Hello %@"
        let formatted = template.localizedWithArgs("Alex")
        XCTAssertEqual(formatted, "Hello Alex")
    }
}
