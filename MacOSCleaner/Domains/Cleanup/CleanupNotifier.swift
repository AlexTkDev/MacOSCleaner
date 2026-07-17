import Foundation

public struct CleanupNotifier: Sendable {
    public init() {}
    
    @MainActor
    public func sendScanComplete(selectedSizeBytes: Int64, showNotifications: Bool) {
        guard showNotifications else { return }
        let title = "cleanup_scan_complete_title".localized
        let body = "cleanup_scan_complete_body".localizedWithArgs(selectedSizeBytes.formattedByteCount())
        NotificationManager.shared.sendNotification(title: title, body: body)
    }
    
    @MainActor
    public func sendCleanupComplete(totalFreedBytes: Int64, showNotifications: Bool) {
        guard showNotifications else { return }
        let title = "cleanup_complete_title".localized
        let body = "cleanup_complete_body".localizedWithArgs(totalFreedBytes.formattedByteCount())
        NotificationManager.shared.sendNotification(title: title, body: body)
    }
}
