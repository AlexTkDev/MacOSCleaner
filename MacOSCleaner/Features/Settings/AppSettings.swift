import SwiftUI
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    case ukrainian = "uk"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .ukrainian: return "Українська"
        }
    }
}

public enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .system: return "theme_system".localized
        case .light:  return "theme_light".localized
        case .dark:   return "theme_dark".localized
        }
    }

    public var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

public enum RefreshInterval: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case seconds5 = "5 sec"
    case seconds10 = "10 sec"
    case seconds30 = "30 sec"

    public var id: String { rawValue }

    public var timeInterval: TimeInterval? {
        switch self {
        case .manual: return nil
        case .seconds5: return 5
        case .seconds10: return 10
        case .seconds30: return 30
        }
    }

    public var localizedName: String {
        switch self {
        case .manual: return "refresh_manual".localized
        case .seconds5: return "refresh_5s".localized
        case .seconds10: return "refresh_10s".localized
        case .seconds30: return "refresh_30s".localized
        }
    }
}

public enum ProcessSortOption: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case name = "Name"
    case threads = "Threads"

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .cpu: return "sort_cpu".localized
        case .memory: return "sort_memory".localized
        case .name: return "sort_name".localized
        case .threads: return "sort_threads".localized
        }
    }
}

@MainActor
@Observable
public final class AppSettings {
    // MARK: - Storage Keys

    private enum Keys {
        static let language = "settings_language"
        static let theme = "settings_theme"
        static let showNotifications = "settings_showNotifications"
        static let showTooltips = "settings_showTooltips"
        static let autoScanOnStartup = "settings_autoScanOnStartup"
        static let emptyTrashDuringCleanup = "settings_emptyTrashDuringCleanup"
        static let bypassTrashOnUninstall = "settings_bypassTrashOnUninstall"
        static let showRelatedFiles = "settings_showRelatedFiles"
        static let emptyTrashImmediately = "settings_emptyTrashImmediately"
        static let skipExpertMode = "settings_skipExpertMode"
        static let processRefreshInterval = "settings_processRefreshInterval"
        static let processSortOption = "settings_processSortOption"
    }

    // MARK: - General

    public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
            LanguageManager.shared.setLanguage(language)
        }
    }

    public var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
            applyTheme()
        }
    }

    public var showNotifications: Bool {
        didSet {
            UserDefaults.standard.set(showNotifications, forKey: Keys.showNotifications)
            if showNotifications {
                NotificationManager.shared.requestAuthorization()
            }
        }
    }

    public var showTooltips: Bool {
        didSet { UserDefaults.standard.set(showTooltips, forKey: Keys.showTooltips) }
    }

    public var autoScanOnStartup: Bool {
        didSet { UserDefaults.standard.set(autoScanOnStartup, forKey: Keys.autoScanOnStartup) }
    }

    // MARK: - Cleanup

    public var emptyTrashDuringCleanup: Bool {
        didSet { UserDefaults.standard.set(emptyTrashDuringCleanup, forKey: Keys.emptyTrashDuringCleanup) }
    }

    // MARK: - Uninstaller

    public var bypassTrashOnUninstall: Bool {
        didSet { UserDefaults.standard.set(bypassTrashOnUninstall, forKey: Keys.bypassTrashOnUninstall) }
    }

    // MARK: - Advanced

    public var showRelatedFiles: Bool {
        didSet { UserDefaults.standard.set(showRelatedFiles, forKey: Keys.showRelatedFiles) }
    }

    public var emptyTrashImmediately: Bool {
        didSet { UserDefaults.standard.set(emptyTrashImmediately, forKey: Keys.emptyTrashImmediately) }
    }

    public var skipExpertMode: Bool {
        didSet { UserDefaults.standard.set(skipExpertMode, forKey: Keys.skipExpertMode) }
    }

    // MARK: - Process Management

    public var processRefreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(processRefreshInterval.rawValue, forKey: Keys.processRefreshInterval)
        }
    }

    public var processSortOption: ProcessSortOption {
        didSet {
            UserDefaults.standard.set(processSortOption.rawValue, forKey: Keys.processSortOption)
        }
    }

    // MARK: - Init

    public init() {
        let defaults = UserDefaults.standard

        let lang = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        self.language = lang
        self.theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        self.showNotifications = defaults.object(forKey: Keys.showNotifications) as? Bool ?? true
        self.showTooltips = defaults.object(forKey: Keys.showTooltips) as? Bool ?? true
        self.autoScanOnStartup = defaults.bool(forKey: Keys.autoScanOnStartup)
        self.emptyTrashDuringCleanup = defaults.bool(forKey: Keys.emptyTrashDuringCleanup)
        self.bypassTrashOnUninstall = defaults.bool(forKey: Keys.bypassTrashOnUninstall)
        self.showRelatedFiles = defaults.object(forKey: Keys.showRelatedFiles) as? Bool ?? true
        self.emptyTrashImmediately = defaults.bool(forKey: Keys.emptyTrashImmediately)
        self.skipExpertMode = defaults.bool(forKey: Keys.skipExpertMode)
        self.processRefreshInterval = RefreshInterval(rawValue: defaults.string(forKey: Keys.processRefreshInterval) ?? "") ?? .manual
        self.processSortOption = ProcessSortOption(rawValue: defaults.string(forKey: Keys.processSortOption) ?? "") ?? .cpu

        LanguageManager.shared.setLanguage(lang)

        if self.showNotifications {
            NotificationManager.shared.requestAuthorization()
        }
    }

    // MARK: - Reset

    public func resetAll() {
        let defaults = UserDefaults.standard
        let allKeys = [
            Keys.language, Keys.theme, Keys.showNotifications, Keys.showTooltips,
            Keys.autoScanOnStartup, Keys.emptyTrashDuringCleanup, Keys.bypassTrashOnUninstall,
            Keys.showRelatedFiles, Keys.emptyTrashImmediately, Keys.skipExpertMode,
            Keys.processRefreshInterval, Keys.processSortOption
        ]
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }

        language = .english
        theme = .system
        showNotifications = true
        showTooltips = true
        autoScanOnStartup = false
        emptyTrashDuringCleanup = false
        bypassTrashOnUninstall = false
        showRelatedFiles = true
        emptyTrashImmediately = false
        skipExpertMode = false
        processRefreshInterval = .manual
        processSortOption = .cpu

        LanguageManager.shared.setLanguage(.english)
    }

    // MARK: - Theme

    public func applyTheme() {
        NSApp.appearance = theme.appearance
    }
}
