import Foundation

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case cleanup = "Cleanup"
    case startupServices = "Startup Services"
    case uninstaller = "Uninstaller"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .cleanup: return "sparkles"
        case .startupServices: return "bolt.horizontal"
        case .uninstaller: return "trash"
        case .settings: return "gear"
        }
    }
}
