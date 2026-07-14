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
    public var pathStack: [URL] = []
    
    // Cache to prevent scanning the same directory twice
    private var scanCache: [URL: [DiskItem]] = [:]
    
    public init() {}
    
    public var filteredItems: [DiskItem] {
        guard selectedCategory != .all else { return items }
        return items.filter { item in
            if item.isDirectory {
                // Directories are kept to allow navigation down the tree
                return true
            } else {
                return item.fileType == selectedCategory
            }
        }
    }
    
    public func selectFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        
        if panel.runModal() == .OK, let url = panel.url {
            startScan(for: url)
        }
    }
    
    public func startScan(for url: URL) {
        scanTask?.cancel()
        
        rootURL = url
        currentURL = url
        pathStack = []
        isScanning = true
        currentScanningName = ""
        items = []
        scanCache.removeAll()
        
        scanTask = Task {
            do {
                let scannedItems = try await scanner.scan(directoryURL: url) { [weak self] folderName in
                    guard let self else { return }
                    Task { @MainActor in
                        self.currentScanningName = folderName
                    }
                }
                
                self.items = scannedItems
                self.scanCache[url] = scannedItems
                self.isScanning = false
            } catch {
                self.logger.error("Scan failed: \(error.localizedDescription)")
                self.isScanning = false
            }
        }
    }
    
    public func navigateTo(item: DiskItem) {
        guard item.isDirectory, let currentURL = currentURL else { return }
        
        pathStack.append(currentURL)
        self.currentURL = item.url
        
        if let cached = scanCache[item.url] {
            self.items = cached
        } else if let children = item.children {
            self.items = children
            self.scanCache[item.url] = children
        } else {
            // Scan subdirectory
            isScanning = true
            items = []
            
            scanTask?.cancel()
            scanTask = Task {
                do {
                    let scannedItems = try await scanner.scan(directoryURL: item.url) { [weak self] folderName in
                        guard let self else { return }
                        Task { @MainActor in
                            self.currentScanningName = folderName
                        }
                    }
                    self.items = scannedItems
                    self.scanCache[item.url] = scannedItems
                    self.isScanning = false
                } catch {
                    self.logger.error("Subdirectory scan failed: \(error.localizedDescription)")
                    self.isScanning = false
                }
            }
        }
    }
    
    public func navigateBack() {
        guard !pathStack.isEmpty else { return }
        let prevURL = pathStack.removeLast()
        self.currentURL = prevURL
        
        if let cached = scanCache[prevURL] {
            self.items = cached
        } else {
            startScan(for: prevURL)
        }
    }
    
    public func moveToTrash(item: DiskItem) {
        Task {
            do {
                _ = try await trashManager.trashItem(at: item.url)
                
                // Remove from local list
                self.items.removeAll { $0.url == item.url }
                
                // Update cache
                if let currentURL = currentURL {
                    scanCache[currentURL] = self.items
                }
            } catch {
                self.logger.error("Failed to move item to trash: \(error.localizedDescription)")
            }
        }
    }
    
    public func showInFinder(item: DiskItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
    }
}
