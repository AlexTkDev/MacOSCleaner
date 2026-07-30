import Foundation

public final class LanguageManager: @unchecked Sendable {
    public static let shared = LanguageManager()
    /// Serializes language switches across XCTest classes that share this singleton.
    public static let testingLock = NSLock()
    
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

        if let langBundle = Self.localizationBundle(for: langCode, in: .main) {
            self._bundle = langBundle
            return
        }
        // Prefer English over Bundle.main (system preferred languages) on miss.
        if let enBundle = Self.localizationBundle(for: "en", in: .main) {
            self._bundle = enBundle
            return
        }
        self._bundle = .main
    }

    /// Resolves `xx.lproj` even when `path(forResource:)` skips non-preferred localizations.
    private static func localizationBundle(for langCode: String, in bundle: Bundle) -> Bundle? {
        if let path = bundle.path(forResource: langCode, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            return langBundle
        }
        if let url = bundle.url(forResource: langCode, withExtension: "lproj"),
           let langBundle = Bundle(path: url.path) {
            return langBundle
        }
        let resourceRoot = bundle.resourceURL ?? bundle.bundleURL.appendingPathComponent("Contents/Resources")
        let direct = resourceRoot.appendingPathComponent("\(langCode).lproj")
        if FileManager.default.fileExists(atPath: direct.path) {
            return Bundle(path: direct.path)
        }
        return nil
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
        case .german: return Locale(identifier: "de_DE")
        case .japanese: return Locale(identifier: "ja_JP")
        case .french: return Locale(identifier: "fr_FR")
        case .chineseSimplified: return Locale(identifier: "zh_Hans_CN")
        case .italian: return Locale(identifier: "it_IT")
        case .portugueseBrazil: return Locale(identifier: "pt_BR")
        }
    }
}
