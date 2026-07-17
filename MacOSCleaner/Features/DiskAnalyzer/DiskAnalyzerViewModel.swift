import Foundation
import SwiftUI
import Observation
import OSLog

@MainActor
@Observable
public final class DiskAnalyzerViewModel {
    private let logger = Logger(subsystem: "input.MacOSCleaner", category: "DiskAnalyzerViewModel")
    private let scanner = DiskScanner()
    private let trashManager = TrashManager()
    
    public var isScanning = false
    public var currentScanningName = ""
    public var rootURL: URL?
    public var currentURL: URL?
    public var items: [DiskItem] = []
    public var selectedCategory: FileCategory = .all
    
    private var scanTask: Task<Void, Never>?
    
    public init() {}
    
    public var filteredItems: [DiskItem] {
        guard selectedCategory != .all else { return items }
        return items.filter { item in
            return item.fileType == selectedCategory
        }
    }
    
    public func selectFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/")
        panel.message = "disk_analyzer_select_folder".localized
        panel.prompt = "disk_analyzer_scan".localized
        
        if panel.runModal() == .OK, let url = panel.url {
            startScan(for: url)
        }
    }
    
    public func startScan(for url: URL) {
        scanTask?.cancel()
        
        rootURL = url
        currentURL = url
        isScanning = true
        currentScanningName = ""
        items = []
        
        scanTask = Task {
            do {
                let scannedItems = try await scanner.scan(directoryURL: url) { [weak self] folderName in
                    guard let self else { return }
                    Task { @MainActor in
                        self.currentScanningName = folderName
                    }
                }
                
                self.items = scannedItems
                self.isScanning = false
            } catch {
                self.logger.error("Scan failed: \(error.localizedDescription)")
                self.isScanning = false
            }
        }
    }

    
    public func moveToTrash(item: DiskItem) {
        Task {
            do {
                _ = try await trashManager.trashItem(at: item.url)
                
                // Remove from local list
                self.items.removeAll { $0.url == item.url }
            } catch {
                self.logger.error("Failed to move item to trash: \(error.localizedDescription)")
            }
        }
    }
    
    public func showInFinder(item: DiskItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
    }
}
