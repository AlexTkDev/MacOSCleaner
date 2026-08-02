import Foundation

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case cleanup = "Cleanup"
    case diskSpace = "Disk Space"
    case duplicates = "Duplicates"
    case processes = "Processes"
    case startupServices = "Startup Services"
    case uninstaller = "Uninstaller"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var localizedTitle: String {
        switch self {
        case .dashboard:      return "menu_dashboard".localized
        case .cleanup:        return "menu_cleanup".localized
        case .diskSpace:      return "menu_disk_space".localized
        case .duplicates:     return "menu_duplicates".localized
        case .processes:      return "menu_processes".localized
        case .startupServices: return "menu_startup_services".localized
        case .uninstaller:    return "menu_uninstaller".localized
        case .settings:       return "menu_settings".localized
        }
    }

    /// Subtitle shown under the window title. Nil for dashboard (no subtitle).
    var localizedSubtitle: String? {
        switch self {
        case .dashboard:       return nil
        case .cleanup:         return "cleanup_subtitle".localized
        case .diskSpace:       return "disk_space_subtitle".localized
        case .duplicates:      return "duplicates_subtitle".localized
        case .processes:       return "processes_subtitle".localized
        case .startupServices: return "startup_subtitle".localized
        case .uninstaller:     return "uninstaller_subtitle".localized
        case .settings:        return "settings_subtitle".localized
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .cleanup: return "sparkles"
        case .diskSpace: return "folder.fill"
        case .duplicates: return "square.on.square"
        case .processes: return "cpu"
        case .startupServices: return "bolt.horizontal"
        case .uninstaller: return "trash"
        case .settings: return "gear"
        }
    }
}

/// Sidebar grouping matching the macOS 27 sidebar layout (flat items + titled sections).
struct SidebarSection: Identifiable {
    let titleKey: String?
    let items: [NavigationItem]

    var id: String { titleKey ?? items.first?.rawValue ?? "" }

    static let all: [SidebarSection] = [
        SidebarSection(titleKey: nil, items: [.dashboard]),
        SidebarSection(titleKey: "sidebar_section_tools", items: [.cleanup, .diskSpace, .duplicates, .uninstaller]),
        SidebarSection(titleKey: "sidebar_section_system", items: [.processes, .startupServices]),
        SidebarSection(titleKey: nil, items: [.settings]),
    ]
}
