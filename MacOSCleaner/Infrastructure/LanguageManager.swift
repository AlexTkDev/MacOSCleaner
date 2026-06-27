import Foundation

public final class LanguageManager: @unchecked Sendable {
    public static let shared = LanguageManager()
    
    private let bundleLock = NSLock()
    private var _bundle: Bundle = .main
    private var _currentLanguage: AppLanguage = .english
    
    public var currentLanguage: AppLanguage {
        bundleLock.lock()
        defer { bundleLock.unlock() }
        return _currentLanguage
    }
    
    public var currentLocale: Locale {
        currentLanguage.locale
    }
    
    private var bundle: Bundle {
        bundleLock.lock()
        defer { bundleLock.unlock() }
        return _bundle
    }
    
    private init() {
        let savedLang = UserDefaults.standard.string(forKey: "settings_language") ?? "en"
        let lang = AppLanguage(rawValue: savedLang) ?? .english
        _currentLanguage = lang
        updateBundle(for: lang.rawValue)
    }
    
    public func setLanguage(_ language: AppLanguage) {
        updateBundle(for: language.rawValue)
        bundleLock.lock()
        _currentLanguage = language
        bundleLock.unlock()
    }
    
    private func updateBundle(for langCode: String) {
        bundleLock.lock()
        defer { bundleLock.unlock() }
        
        guard let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
              let langBundle = Bundle(path: path) else {
            self._bundle = .main
            return
        }
        self._bundle = langBundle
    }
    
    public func localizedString(_ key: String) -> String {
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

extension AppLanguage {
    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .russian: return Locale(identifier: "ru_RU")
        case .ukrainian: return Locale(identifier: "uk_UA")
        case .spanish: return Locale(identifier: "es_ES")
        }
    }
}
