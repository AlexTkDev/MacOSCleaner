import XCTest
@testable import MacOSCleaner

final class OrphanScannerTests: XCTestCase {
    var scanner: OrphanScanner!
    var safetyManager: SafetyManager!

    override func setUp() {
        super.setUp()
        // Initialize with default or mock dependencies as appropriate for testing
        let fileSystemContext: FileSystemContext = .production
        safetyManager = SafetyManager(homeDirectory: fileSystemContext.homePath, fileSystemContext: fileSystemContext)
        scanner = OrphanScanner(safetyManager: safetyManager)
    }

    override func tearDown() {
        scanner = nil
        safetyManager = nil
        super.tearDown()
    }

    func testOrphanScannerInitialization() {
        XCTAssertNotNil(scanner)
    }
}
