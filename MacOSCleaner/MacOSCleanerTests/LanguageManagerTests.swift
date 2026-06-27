import XCTest
@testable import MacOSCleaner

final class LanguageManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset to English before each test
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
