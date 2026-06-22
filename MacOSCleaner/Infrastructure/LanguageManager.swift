import Foundation

public final class LanguageManager: @unchecked Sendable {
    public static let shared = LanguageManager()
    
    private let bundleLock = NSLock()
    private var _bundle: Bundle = .main
    
    private var bundle: Bundle {
        bundleLock.lock()
        defer { bundleLock.unlock() }
        return _bundle
    }
    
    private init() {
        // По умолчанию инициализируем английским или сохраненным
        let savedLang = UserDefaults.standard.string(forKey: "settings_language") ?? "en"
        updateBundle(for: savedLang)
    }
    
    public func setLanguage(_ language: AppLanguage) {
        updateBundle(for: language.rawValue)
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
