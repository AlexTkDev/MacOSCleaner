import Foundation

public struct CleanupNotifier: Sendable {
    public init() {}
    
    @MainActor
    public func sendScanComplete(selectedSizeMB: Int, showNotifications: Bool) {
        guard showNotifications else { return }
        let title = "cleanup_scan_complete_title".localized
        let body = "cleanup_scan_complete_body".localizedWithArgs(selectedSizeMB)
        NotificationManager.shared.sendNotification(title: title, body: body)
    }
    
    @MainActor
    public func sendCleanupComplete(totalFreedMB: Int, showNotifications: Bool) {
        guard showNotifications else { return }
        let title = "cleanup_complete_title".localized
        let body = "cleanup_complete_body".localizedWithArgs(totalFreedMB)
        NotificationManager.shared.sendNotification(title: title, body: body)
    }
}
