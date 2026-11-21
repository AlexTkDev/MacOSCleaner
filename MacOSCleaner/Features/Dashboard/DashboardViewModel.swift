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
    @Published var completedCategoriesCount: Int = 0
    @Published var lastUpdatedAt: Date? = nil
    let totalScanCategoriesCount: Int = 5
    private var isRefreshing: Bool = false

    private struct CategorySpec: Sendable {
        let id: String
        let labelKey: String
        let color: Color
        let gradientColors: [Color]
        let iconName: String
        let paths: [String]
    }

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

    private static func allCategorySpecs(home: String) -> [CategorySpec] {
        [
            CategorySpec(
                id: "caches",
                labelKey: "dashboard_radar_caches",
                color: Color(red: 0.0, green: 0.75, blue: 0.95),
                gradientColors: [Color(red: 0.0, green: 0.75, blue: 0.95), Color(red: 0.0, green: 0.55, blue: 0.85)],
                iconName: "archivebox.fill",
                paths: ["\(home)/Library/Caches", "/Library/Caches"]
            ),
            CategorySpec(
                id: "logs",
                labelKey: "dashboard_radar_logs",
                color: Color(red: 1.0, green: 0.6, blue: 0.0),
                gradientColors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 0.95, green: 0.45, blue: 0.0)],
                iconName: "doc.text.fill",
                paths: ["\(home)/Library/Logs", "/Library/Logs"]
            ),
            CategorySpec(
                id: "dev",
                labelKey: "dashboard_radar_dev",
                color: Color(red: 0.15, green: 0.55, blue: 1.0),
                gradientColors: [Color(red: 0.15, green: 0.55, blue: 1.0), Color(red: 0.35, green: 0.35, blue: 0.95)],
                iconName: "hammer.fill",
                paths: ["\(home)/Library/Developer"]
            ),
            CategorySpec(
                id: "apps",
                labelKey: "dashboard_radar_apps",
                color: Color(red: 0.65, green: 0.35, blue: 0.95),
                gradientColors: [Color(red: 0.65, green: 0.35, blue: 0.95), Color(red: 0.45, green: 0.2, blue: 0.85)],
                iconName: "app.badge.fill",
                paths: ["/Applications", "\(home)/Applications", "/System/Applications"]
            ),
            CategorySpec(
                id: "media",
                labelKey: "dashboard_radar_media",
                color: Color(red: 0.95, green: 0.3, blue: 0.55),
                gradientColors: [Color(red: 0.95, green: 0.3, blue: 0.55), Color(red: 0.9, green: 0.2, blue: 0.35)],
                iconName: "photo.stack.fill",
                paths: ["\(home)/Music", "\(home)/Pictures", "\(home)/Movies"]
            ),
            CategorySpec(
                id: "other",
                labelKey: "dashboard_radar_other",
                color: Color(red: 0.45, green: 0.5, blue: 0.6),
                gradientColors: [Color(red: 0.45, green: 0.5, blue: 0.6), Color(red: 0.3, green: 0.35, blue: 0.45)],
                iconName: "square.grid.2x2.fill",
                paths: []
            ),
        ]
    }

    private static func buildCategoryItems(
        specs: [CategorySpec],
        sizes: [String: Int64],
        completedKeys: Set<String>,
        otherBytes: Int64,
        isScanning: Bool
    ) -> [DiskCategoryItem] {
        specs.compactMap { spec in
            if spec.id == "other" {
                if !isScanning && otherBytes <= 0 { return nil }
                return DiskCategoryItem(
                    id: spec.id,
                    label: spec.labelKey.localized,
                    bytes: isScanning ? 0 : otherBytes,
                    color: spec.color,
                    gradientColors: spec.gradientColors,
                    iconName: spec.iconName,
                    isScanning: isScanning
                )
            }
            let bytes = sizes[spec.id, default: 0]
            if !isScanning && bytes <= 0 { return nil }
            let itemScanning = isScanning && !completedKeys.contains(spec.id)
            return DiskCategoryItem(
                id: spec.id,
                label: spec.labelKey.localized,
                bytes: bytes,
                color: spec.color,
                gradientColors: spec.gradientColors,
                iconName: spec.iconName,
                isScanning: itemScanning
            )
        }
    }

    private func fetchCategoryData() async {
        isCategoriesLoading = true
        completedCategoriesCount = 0

        let home = NSHomeDirectory()
        let specs = Self.allCategorySpecs(home: home)
        let scanSpecs = specs.filter { !$0.paths.isEmpty }

        var liveSizes: [String: Int64] = [:]
        var completedKeys = Set<String>()
        diskCategories = Self.buildCategoryItems(
            specs: specs,
            sizes: liveSizes,
            completedKeys: completedKeys,
            otherBytes: 0,
            isScanning: true
        )

        let stream = AsyncStream<(key: String, bytes: Int64, finished: Bool)> { continuation in
            let producer = Task {
                await withTaskGroup(of: Void.self) { group in
                    for spec in scanSpecs {
                        group.addTask {
                            var completedPathBytes: Int64 = 0
                            for path in spec.paths {
                                let baseBytes = completedPathBytes
                                let pathSize = await Self.calculatePathSize(path) { partial in
                                    continuation.yield((spec.id, baseBytes + partial, false))
                                }
                                completedPathBytes += pathSize
                                continuation.yield((spec.id, completedPathBytes, false))
                            }
                            continuation.yield((spec.id, completedPathBytes, true))
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                producer.cancel()
            }
        }

        for await event in stream {
            liveSizes[event.key] = event.bytes
            if event.finished {
                completedKeys.insert(event.key)
                completedCategoriesCount = completedKeys.count
            }
            diskCategories = Self.buildCategoryItems(
                specs: specs,
                sizes: liveSizes,
                completedKeys: completedKeys,
                otherBytes: 0,
                isScanning: true
            )
        }

        // "Other" = used space not accounted for by the 5 scanned categories.
        let identifiedSum = scanSpecs.reduce(Int64(0)) { $0 + liveSizes[$1.id, default: 0] }
        let otherUsed = max(0, usedDiskSpace - identifiedSum)
        diskCategories = Self.buildCategoryItems(
            specs: specs,
            sizes: liveSizes,
            completedKeys: completedKeys,
            otherBytes: otherUsed,
            isScanning: false
        )
        isCategoriesLoading = false
    }

    nonisolated static func calculatePathSize(_ path: String) async -> Int64 {
        await calculatePathSize(path, onProgress: nil)
    }

    nonisolated static func calculatePathSize(
        _ path: String,
        onProgress: (@Sendable (Int64) -> Void)?
    ) async -> Int64 {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false

            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
            if !isDirectory.boolValue {
                let attribs = try? fm.attributesOfItem(atPath: path)
                return (attribs?[.size] as? Int64) ?? 0
            }

            let keys: Set<URLResourceKey> = [
                .fileSizeKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey,
            ]
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            var totalSize: Int64 = 0
            var yieldCount = 0
            let clock = ContinuousClock()
            var lastReport = clock.now
            var finished = false

            while !finished {
                if Task.isCancelled { break }
                autoreleasepool {
                    var batchCount = 0
                    while batchCount < 256 {
                        guard let fileURL = enumerator.nextObject() as? URL else {
                            finished = true
                            return
                        }
                        batchCount += 1

                        if FileManager.shouldExclude(url: fileURL) {
                            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                                enumerator.skipDescendants()
                            }
                            continue
                        }
                        guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
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
                    }
                }

                if let onProgress, clock.now - lastReport >= .milliseconds(180) {
                    lastReport = clock.now
                    onProgress(totalSize)
                }
                if yieldCount >= 2000 {
                    yieldCount = 0
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
