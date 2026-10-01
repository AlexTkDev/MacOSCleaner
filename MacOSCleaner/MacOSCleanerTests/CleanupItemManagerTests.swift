import Foundation
import Testing
@testable import MacOSCleaner

@Suite("CleanupItemManager")
struct CleanupItemManagerTests {
    
    @Test("appendFileItem keeps isCommandBacked and size constraints")
    func testAppendFileItemIsCommandBacked() async {
        let manager = CleanupItemManager()
        
        manager.appendFileItem(
            path: "command://dns/flush",
            sizeBytes: 15 * 1024 * 1024,
            modificationDate: nil,
            isDirectory: false,
            category: "DNS Cache",
            parentName: nil,
            isSelected: true,
            isCommandBacked: true
        )
        
        #expect(manager.items.count == 1)
        let rootItem = manager.items[0]
        #expect(rootItem.children.count == 1)
        
        let child = rootItem.children[0]
        #expect(child.isCommandBacked == true)
        #expect(child.sizeMB == 15) // no max(1, size) minimum for command backed 
        #expect(child.path == "command://dns/flush")
    }
    
    @Test("allSelectedPaths returns correct selected items including command backed")
    func testAllSelectedPaths() async {
        let manager = CleanupItemManager()
        
        manager.appendFileItem(
            path: "/Users/alex/Cache1",
            sizeBytes: 1000,
            modificationDate: nil,
            isDirectory: true,
            category: "Caches",
            parentName: nil,
            isSelected: true
        )
        
        manager.appendFileItem(
            path: "command://font/cache-clear",
            sizeBytes: 2000,
            modificationDate: nil,
            isDirectory: false,
            category: "Font Cache",
            parentName: nil,
            isSelected: false,
            isCommandBacked: true
        )
        
        let selected = manager.allSelectedPaths()
        #expect(selected.contains("/Users/alex/Cache1"))
        #expect(!selected.contains("command://font/cache-clear"))
        
        // toggle selection
        manager.setSelection(underParentLabel: "Font Cache", isSelected: true)
        
        let selectedAfterToggle = manager.allSelectedPaths()
        #expect(selectedAfterToggle.contains("/Users/alex/Cache1"))
        #expect(selectedAfterToggle.contains("command://font/cache-clear"))
    }
    
    @Test("selectedCleanupCategories filters correctly")
    func testSelectedCleanupCategories() async {
        let manager = CleanupItemManager()
        manager.appendFileItem(
            path: "/Test/Cache",
            sizeBytes: 10 * 1024 * 1024,
            modificationDate: nil,
            isDirectory: true,
            category: CleanupCategory.localizedGroupTitle(for: "user_logs"),
            parentName: nil,
            isSelected: true
        )
        
        let all: [CleanupCategory] = [.appCaches, .userLogs, .systemCaches]
        let selected = manager.selectedCleanupCategories(from: all)
        
        #expect(selected.contains(.userLogs))
        #expect(!selected.contains(.appCaches))
    }
}
