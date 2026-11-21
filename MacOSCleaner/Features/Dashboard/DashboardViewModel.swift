import SwiftUI
import Foundation
import OSLog

private extension Logger {
    static let dashboard = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "DashboardViewModel")
}

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var totalDiskSpace: Int64 = 0
    @Published var freeDiskSpace: Int64 = 0
    @Published var totalFreedBytes: Int64 = 0
    @Published var cleanupCount: Int = 0
    @Published var recentTransactions: [CleanupTransaction] = []
    @Published var recentRecords: [CleanupRecord] = []
    @Published var systemInfo: SystemInfo = .current
    
    // Disk Categories (Donut Chart)
    @Published var isCategoriesLoading: Bool = true
    @Published var diskCategories: [DiskCategoryItem] = []
    @Published var lastUpdatedAt: Date? = nil
    private var isRefreshing: Bool = false

    private let journal: TransactionJournal

    init(journal: TransactionJournal) {
        self.journal = journal
    }

    func refreshIfNeeded() async {
        if lastUpdatedAt == nil && !isRefreshing {
            await refresh()
        } else {
            systemInfo = .current
            await fetchDiskUsage()
            await fetchHistory()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        systemInfo = .current
        await fetchDiskUsage()
        await fetchHistory()
        await fetchCategoryData()
        lastUpdatedAt = Date()
    }
    
    private func fetchDiskUsage() async {
        let fileManager = FileManager.default
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        
        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            totalDiskSpace = Int64(values.volumeTotalCapacity ?? 0)
            freeDiskSpace = Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            Logger.dashboard.error("Failed to fetch disk usage: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func fetchHistory() async {
        do {
            let allTransactions = try await journal.loadAll()
            recentTransactions = Array(allTransactions.reversed().prefix(5))
            let records = allTransactions.reversed().map { CleanupRecord(transaction: $0) }
            recentRecords = Array(records.prefix(3))
            totalFreedBytes = allTransactions.reduce(0) { sum, transaction in
                sum + transaction.operations.reduce(0) { $0 + $1.bytesFreed }
            }
            cleanupCount = allTransactions.count
        } catch {
            Logger.dashboard.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func fetchCategoryData() async {
        isCategoriesLoading = true
        let home = NSHomeDirectory()
        
        let categoryPaths: [(key: String, paths: [String])] = [
            ("caches", ["\(home)/Library/Caches", "/Library/Caches"]),
            ("logs",   ["\(home)/Library/Logs", "/Library/Logs"]),
            ("dev",    ["\(home)/Library/Developer"]),
            ("apps",   ["/Applications", "\(home)/Applications", "/System/Applications"]),
            ("media",  ["\(home)/Music", "\(home)/Pictures", "\(home)/Movies"])
        ]
        
        var calculatedSizes: [String: Int64] = [:]
        
        await withTaskGroup(of: (String, Int64).self) { group in
            for entry in categoryPaths {
                let paths = entry.paths
                let key = entry.key
                group.addTask {
                    var total: Int64 = 0
                    for path in paths {
                        total += await Self.calculatePathSize(path)
                    }
                    return (key, total)
                }
            }
            for await (key, size) in group {
                calculatedSizes[key] = size
            }
        }
        
        let cachesSize = calculatedSizes["caches", default: 0]
        let logsSize   = calculatedSizes["logs",   default: 0]
        let devSize    = calculatedSizes["dev",    default: 0]
        let appsSize   = calculatedSizes["apps",   default: 0]
        let mediaSize  = calculatedSizes["media",  default: 0]
        let identifiedSum = cachesSize + logsSize + devSize + appsSize + mediaSize
        // "Other" = used space not accounted for by the 5 categories
        // Free space is shown as a separate explicit segment
        let otherUsed = max(0, usedDiskSpace - identifiedSum)
        
        var items: [DiskCategoryItem] = []
        if cachesSize > 0 {
            items.append(DiskCategoryItem(
                label: "dashboard_radar_caches".localized,
                bytes: cachesSize,
                color: Color(red: 0.0, green: 0.75, blue: 0.95),
                gradientColors: [Color(red: 0.0, green: 0.75, blue: 0.95), Color(red: 0.0, green: 0.55, blue: 0.85)],
                iconName: "archivebox.fill"
            ))
        }
        if logsSize > 0 {
            items.append(DiskCategoryItem(
                label: "dashboard_radar_logs".localized,
                bytes: logsSize,
                color: Color(red: 1.0, green: 0.6, blue: 0.0),
                gradientColors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 0.95, green: 0.45, blue: 0.0)],
                iconName: "doc.text.fill"
            ))
        }
        if devSize > 0 {
            items.append(DiskCategoryItem(
                label: "dashboard_radar_dev".localized,
                bytes: devSize,
                color: Color(red: 0.15, green: 0.55, blue: 1.0),
                gradientColors: [Color(red: 0.15, green: 0.55, blue: 1.0), Color(red: 0.35, green: 0.35, blue: 0.95)],
                iconName: "hammer.fill"
            ))
        }
        if appsSize > 0 {
            items.append(DiskCategoryItem(
                label: "dashboard_radar_apps".localized,
                bytes: appsSize,
                color: Color(red: 0.65, green: 0.35, blue: 0.95),
                gradientColors: [Color(red: 0.65, green: 0.35, blue: 0.95), Color(red: 0.45, green: 0.2, blue: 0.85)],
                iconName: "app.badge.fill"
            ))
        }
        if mediaSize > 0 {
            items.append(DiskCategoryItem(
                label: "dashboard_radar_media".localized,
                bytes: mediaSize,
                color: Color(red: 0.95, green: 0.3, blue: 0.55),
                gradientColors: [Color(red: 0.95, green: 0.3, blue: 0.55), Color(red: 0.9, green: 0.2, blue: 0.35)],
                iconName: "photo.stack.fill"
            ))
        }
        if otherUsed > 0 {
            items.append(DiskCategoryItem(
                label: "dashboard_radar_other".localized,
                bytes: otherUsed,
                color: Color(red: 0.45, green: 0.5, blue: 0.6),
                gradientColors: [Color(red: 0.45, green: 0.5, blue: 0.6), Color(red: 0.3, green: 0.35, blue: 0.45)],
                iconName: "square.grid.2x2.fill"
            ))
        }
        
        self.diskCategories = items
        self.isCategoriesLoading = false
    }
    
    nonisolated static func calculatePathSize(_ path: String) async -> Int64 {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
            if !isDirectory.boolValue {
                let attribs = try? fm.attributesOfItem(atPath: path)
                return (attribs?[.size] as? Int64) ?? 0
            }

            let keys: [URLResourceKey] = [
                .fileSizeKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
            ]
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            var totalSize: Int64 = 0
            var yieldCount = 0

            while let fileURL = enumerator.nextObject() as? URL {
                if FileManager.shouldExclude(url: fileURL) {
                    if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isSymbolicLink == true {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if FileManager.isNotDownloadedUbiquitous(values) {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if values.isDirectory == true {
                    continue
                }
                totalSize += Int64(values.fileSize ?? 0)
                yieldCount += 1
                if yieldCount % 2000 == 0 {
                    await Task.yield()
                }
            }

            return totalSize
        }.value
    }
    
    var usedDiskSpace: Int64 {
        totalDiskSpace - freeDiskSpace
    }
}
