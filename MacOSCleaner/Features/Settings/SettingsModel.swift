import SwiftUI

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general
    case cleanup
    case automation
    case processes
    case advanced
    case about

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "settings_category_general".localized
        case .cleanup: return "settings_category_cleanup".localized
        case .automation: return "settings_category_automation".localized
        case .processes: return "settings_category_processes".localized
        case .advanced: return "settings_category_advanced".localized
        case .about: return "settings_category_about".localized
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .cleanup: return "trash.circle.fill"
        case .automation: return "waveform"
        case .processes: return "cpu"
        case .advanced: return "wrench.and.screwdriver.fill"
        case .about: return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return .gray
        case .cleanup: return .teal
        case .automation: return .purple
        case .processes: return .orange
        case .advanced: return .indigo
        case .about: return .cyan
        }
    }
}

// MARK: - Settings Item & Search Model

struct SettingsItem: Identifiable, Hashable {
    let id: String
    let category: SettingsCategory
    let titleKey: String
    let subtitleKey: String?
    let keywords: [String]
    let iconName: String

    var title: String { titleKey.localized }
    var subtitle: String? { subtitleKey?.localized }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SettingsItem, rhs: SettingsItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Search Registry

struct SettingsSearchRegistry {
    static let allItems: [SettingsItem] = [
        // General
        SettingsItem(id: "language", category: .general, titleKey: "settings_language", subtitleKey: "settings_language_sub", keywords: ["language", "язык", "locale", "english", "ukrainian", "russian", "локализация"], iconName: "globe"),
        SettingsItem(id: "theme", category: .general, titleKey: "settings_theme", subtitleKey: "settings_theme_sub", keywords: ["theme", "тема", "dark", "light", "appearance", "оформление", "вид"], iconName: "paintbrush"),
        SettingsItem(id: "autoScan", category: .general, titleKey: "settings_auto_scan", subtitleKey: "settings_auto_scan_sub", keywords: ["auto", "scan", "startup", "автосканирование", "авто", "запуск"], iconName: "play.circle"),
        SettingsItem(id: "reset", category: .general, titleKey: "settings_forget_everything", subtitleKey: "settings_forget_description", keywords: ["reset", "forget", "danger", "сброс", "очистить всё", "сбросить"], iconName: "arrow.counterclockwise"),

        // Permissions
        SettingsItem(id: "fda", category: .general, titleKey: "permissions.full_disk_access", subtitleKey: "settings_fda_body", keywords: ["fda", "full disk access", "permissions", "диск", "права", "полный доступ"], iconName: "lock.shield"),
        SettingsItem(id: "notifications", category: .general, titleKey: "settings_notifications", subtitleKey: "settings_notifications_enable_sub", keywords: ["notifications", "уведомления", "alerts", "алерты"], iconName: "bell"),

        // Cleanup
        SettingsItem(id: "scanMode", category: .cleanup, titleKey: "scan_mode", subtitleKey: "settings_scan_mode_sub", keywords: ["scan", "uninstaller", "mode", "режим", "сканирование"], iconName: "slider.horizontal.3"),
        SettingsItem(id: "emptyTrash", category: .cleanup, titleKey: "settings_empty_trash_during_cleanup", subtitleKey: "settings_empty_trash_cleanup_sub", keywords: ["empty", "trash", "очистка", "корзина"], iconName: "trash"),
        SettingsItem(id: "bypassTrash", category: .cleanup, titleKey: "settings_bypass_trash_on_uninstall", subtitleKey: "settings_bypass_trash_sub", keywords: ["bypass", "direct", "delete", "обход корзины", "удаление"], iconName: "xmark.bin"),

        // Automation & AI
        SettingsItem(id: "siri", category: .automation, titleKey: "settings_siri_toggle_title", subtitleKey: "settings_enable_siri_sub", keywords: ["siri", "voice", "сири", "голос", "команды"], iconName: "waveform"),
        SettingsItem(id: "shortcuts", category: .automation, titleKey: "settings_automator_toggle_title", subtitleKey: "settings_enable_shortcuts_sub", keywords: ["shortcuts", "automator", "быстрые команды", "автоматизация"], iconName: "square.stack.3d.up"),
        SettingsItem(id: "enableAI", category: .automation, titleKey: "settings_enable_ai", subtitleKey: "settings_enable_ai_sub", keywords: ["ai", "apple intelligence", "smart", "искусственный интеллект", "модель"], iconName: "sparkles"),

        // Processes
        SettingsItem(id: "refreshInterval", category: .processes, titleKey: "settings_refresh_interval", subtitleKey: "settings_refresh_interval_sub", keywords: ["refresh", "interval", "processes", "процессы", "интервал"], iconName: "timer"),
        SettingsItem(id: "sortBy", category: .processes, titleKey: "settings_sort_option_title", subtitleKey: "settings_sort_option_sub", keywords: ["sort", "cpu", "memory", "сортировка", "память"], iconName: "arrow.up.arrow.down"),

        // Advanced
        SettingsItem(id: "relatedFiles", category: .advanced, titleKey: "settings_show_related_app_files", subtitleKey: "settings_show_related_app_files_sub", keywords: ["related", "advanced", "файлы", "связанные"], iconName: "doc.on.doc"),
        SettingsItem(id: "debugMode", category: .advanced, titleKey: "settings_debug_mode", subtitleKey: "settings_debug_mode_sub", keywords: ["debug", "log", "logs", "дебаг", "логи", "отладка"], iconName: "terminal")
    ]

    static func search(_ query: String) -> [SettingsItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allItems.filter { item in
            item.title.lowercased().contains(q) ||
            item.titleKey.lowercased().contains(q) ||
            (item.subtitle?.lowercased().contains(q) ?? false) ||
            (item.subtitleKey?.lowercased().contains(q) ?? false) ||
            item.keywords.contains(where: { $0.lowercased().contains(q) })
        }
    }
}
