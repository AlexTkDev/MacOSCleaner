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
    let title: String
    let subtitle: String?
    let keywords: [String]
    let iconName: String

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
        SettingsItem(id: "language", category: .general, title: "Language", subtitle: "App display language", keywords: ["language", "язык", "locale", "english", "ukrainian"], iconName: "globe"),
        SettingsItem(id: "theme", category: .general, title: "Theme", subtitle: "Appearance light/dark mode", keywords: ["theme", "тема", "dark", "light", "appearance"], iconName: "paintbrush"),
        SettingsItem(id: "autoScan", category: .general, title: "Auto Scan", subtitle: "Automatically scan on app startup", keywords: ["auto", "scan", "startup", "автосканирование"], iconName: "play.circle"),
        SettingsItem(id: "reset", category: .general, title: "Reset All Settings", subtitle: "Restore factory defaults", keywords: ["reset", "forget", "danger", "сброс"], iconName: "arrow.counterclockwise"),

        // Permissions
        SettingsItem(id: "fda", category: .general, title: "Full Disk Access", subtitle: "Required to scan protected system files", keywords: ["fda", "full disk access", "permissions", "диск", "права"], iconName: "lock.shield"),
        SettingsItem(id: "notifications", category: .general, title: "Notifications", subtitle: "Cleanup and status alerts", keywords: ["notifications", "уведомления", "alerts"], iconName: "bell"),
        SettingsItem(id: "trashAccess", category: .general, title: "Trash Access", subtitle: "Empty trash access", keywords: ["trash", "корзина", "access"], iconName: "trash"),

        // Cleanup
        SettingsItem(id: "scanMode", category: .cleanup, title: "Uninstaller Scan Mode", subtitle: "Safe vs Balanced vs Deep", keywords: ["scan", "uninstaller", "mode", "режим"], iconName: "slider.horizontal.3"),
        SettingsItem(id: "emptyTrash", category: .cleanup, title: "Empty Trash During Cleanup", subtitle: "Empty trash after clean", keywords: ["empty", "trash", "очистка"], iconName: "trash"),
        SettingsItem(id: "bypassTrash", category: .cleanup, title: "Bypass Trash On Uninstall", subtitle: "Delete directly without trash", keywords: ["bypass", "direct", "delete"], iconName: "xmark.bin"),

        // Automation & AI
        SettingsItem(id: "siri", category: .automation, title: "Siri Integration", subtitle: "Control cleanup with Siri", keywords: ["siri", "voice", "сири", "голос"], iconName: "waveform"),
        SettingsItem(id: "shortcuts", category: .automation, title: "Shortcuts & Automator", subtitle: "Run cleanup in workflows", keywords: ["shortcuts", "automator", "быстрые команды"], iconName: "square.stack.3d.up"),
        SettingsItem(id: "enableAI", category: .automation, title: "Apple Intelligence", subtitle: "Smart cleanup recommendations", keywords: ["ai", "apple intelligence", "smart", "искусственный интеллект"], iconName: "sparkles"),

        // Processes
        SettingsItem(id: "refreshInterval", category: .processes, title: "Refresh Interval", subtitle: "Process monitor frequency", keywords: ["refresh", "interval", "processes", "процессы"], iconName: "timer"),
        SettingsItem(id: "sortBy", category: .processes, title: "Process Sorting", subtitle: "Sort by CPU or Memory", keywords: ["sort", "cpu", "memory", "сортировка"], iconName: "arrow.up.arrow.down"),

        // Advanced
        SettingsItem(id: "relatedFiles", category: .advanced, title: "Show Related Files", subtitle: "Advanced uninstaller finding", keywords: ["related", "advanced", "файлы"], iconName: "doc.on.doc")
    ]

    static func search(_ query: String) -> [SettingsItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allItems.filter { item in
            item.title.lowercased().contains(q) ||
            (item.subtitle?.lowercased().contains(q) ?? false) ||
            item.keywords.contains(where: { $0.lowercased().contains(q) })
        }
    }
}
