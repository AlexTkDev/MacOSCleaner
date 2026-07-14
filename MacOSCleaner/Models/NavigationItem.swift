import Foundation

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case cleanup = "Cleanup"
    case diskSpace = "Disk Space"
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
        case .processes:      return "menu_processes".localized
        case .startupServices: return "menu_startup_services".localized
        case .uninstaller:    return "menu_uninstaller".localized
        case .settings:       return "menu_settings".localized
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .cleanup: return "sparkles"
        case .diskSpace: return "folder.fill"
        case .processes: return "cpu"
        case .startupServices: return "bolt.horizontal"
        case .uninstaller: return "trash"
        case .settings: return "gear"
        }
    }
}
