import Foundation

public extension String {
    var localized: String {
        LanguageManager.shared.localizedString(self)
    }
    
    func localizedWithArgs(_ arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}

public extension ByteCountFormatter {
    static func localizedString(fromByteCount count: Int64, countStyle: ByteCountFormatter.CountStyle) -> String {
        if abs(count) < 1000 {
            let isRussian = LanguageManager.shared.currentLocale.language.languageCode?.identifier == "ru" ||
                            LanguageManager.shared.currentLocale.language.languageCode?.identifier == "uk"
            let unit = isRussian ? "Б" : "B"
            return "\(count) \(unit)"
        }
        let style: ByteCountFormatStyle.Style = (countStyle == .memory) ? .memory : .file
        return count.formatted(.byteCount(style: style).locale(LanguageManager.shared.currentLocale))
    }
    
    static func makeLocalized(countStyle: ByteCountFormatter.CountStyle = .file) -> ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = countStyle
        return f
    }
}

public extension Int64 {
    func formattedByteCount(style: ByteCountFormatStyle.Style = .file, forceGB: Bool = false) -> String {
        if forceGB {
            let formatter = ByteCountFormatter.makeLocalized(countStyle: style == .memory ? .memory : .file)
            formatter.allowedUnits = .useGB
            return formatter.string(fromByteCount: self)
        }
        if abs(self) < 1000 {
            let isRussian = LanguageManager.shared.currentLocale.language.languageCode?.identifier == "ru" ||
                            LanguageManager.shared.currentLocale.language.languageCode?.identifier == "uk"
            let unit = isRussian ? "Б" : "B"
            return "\(self) \(unit)"
        }
        let locale = LanguageManager.shared.currentLocale
        return self.formatted(.byteCount(style: style).locale(locale))
    }
}

public extension DateFormatter {
    static func makeLocalized(dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .none) -> DateFormatter {
        let f = DateFormatter()
        f.dateStyle = dateStyle
        f.timeStyle = timeStyle
        f.locale = LanguageManager.shared.currentLocale
        return f
    }
    
    static func makeLocalized(withFormat dateFormat: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = dateFormat
        f.locale = LanguageManager.shared.currentLocale
        return f
    }
}
