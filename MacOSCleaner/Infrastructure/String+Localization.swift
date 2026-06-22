import Foundation

public extension String {
    var localized: String {
        LanguageManager.shared.localizedString(self)
    }
    
    func localizedWithArgs(_ arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}
