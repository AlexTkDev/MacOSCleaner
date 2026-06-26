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
        let f = ByteCountFormatter()
        f.countStyle = countStyle
        return f.string(fromByteCount: count)
    }
    
    static func makeLocalized(countStyle: ByteCountFormatter.CountStyle = .file) -> ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = countStyle
        return f
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
