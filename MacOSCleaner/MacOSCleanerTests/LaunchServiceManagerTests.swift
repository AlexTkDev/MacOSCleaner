import XCTest
@testable import MacOSCleaner

final class LaunchServiceManagerTests: XCTestCase {
    var manager: LaunchServiceManager!
    var tempDir: URL!
    var fileManager: FileManager!

    override func setUp() async throws {
        fileManager = .default
        let home = NSHomeDirectory()
        tempDir = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MacOSCleanerTests")

        if fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.removeItem(at: tempDir)
        }
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        manager = LaunchServiceManager(searchPaths: [tempDir.path])
        await manager.setSystemVendorPrefixes(["com.apple."])
    }

    override func tearDown() async throws {
        if fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.removeItem(at: tempDir)
        }
        await manager.setSystemVendorPrefixes(["com.apple."])
        manager = nil
    }

    // MARK: - Scan Tests

    func testScanDetectsPlists() async throws {
        let plistURL = tempDir.appendingPathComponent("com.test.agent.plist")
        let plistContent: [String: Any] = ["Label": "com.test.agent"]
        let data = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
        try data.write(to: plistURL)

        let services = try await manager.scan()

        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services.first?.id, "com.test.agent")
        XCTAssertEqual(services.first?.path, plistURL.path)
    }

    func testScanFiltersNonPlists() async throws {
        let txtURL = tempDir.appendingPathComponent("not_a_plist.txt")
        try "test".write(to: txtURL, atomically: true, encoding: .utf8)

        let services = try await manager.scan()
        XCTAssertTrue(services.isEmpty)
    }

    func testScanSortsByName() async throws {
        let plist1 = tempDir.appendingPathComponent("b.plist")
        let plist2 = tempDir.appendingPathComponent("a.plist")

        let data1 = try PropertyListSerialization.data(fromPropertyList: ["Label": "b"], format: .xml, options: 0)
        let data2 = try PropertyListSerialization.data(fromPropertyList: ["Label": "a"], format: .xml, options: 0)

        try data1.write(to: plist1)
        try data2.write(to: plist2)

        let services = try await manager.scan()
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].id, "a")
        XCTAssertEqual(services[1].id, "b")
    }

    func testScanDetectsMultiplePaths() async throws {
        let dir1 = tempDir.appendingPathComponent("path1")
        let dir2 = tempDir.appendingPathComponent("path2")
        try fileManager.createDirectory(at: dir1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dir2, withIntermediateDirectories: true)

        let plist1 = dir1.appendingPathComponent("1.plist")
        let plist2 = dir2.appendingPathComponent("2.plist")

        try PropertyListSerialization.data(fromPropertyList: ["Label": "1"], format: .xml, options: 0).write(to: plist1)
        try PropertyListSerialization.data(fromPropertyList: ["Label": "2"], format: .xml, options: 0).write(to: plist2)

        let multiManager = LaunchServiceManager(searchPaths: [dir1.path, dir2.path])
        let services = try await multiManager.scan()

        XCTAssertEqual(services.count, 2)
        let labels = Set(services.map { $0.id })
        XCTAssertTrue(labels.contains("1"))
        XCTAssertTrue(labels.contains("2"))
    }

    func testScanAssignsUserCategory() async throws {
        let plist = tempDir.appendingPathComponent("com.user.agent.plist")
        try PropertyListSerialization.data(
            fromPropertyList: ["Label": "com.user.agent"],
            format: .xml, options: 0
        ).write(to: plist)

        let services = try await manager.scan()

        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services.first?.category, .user)
    }

    // MARK: - Categorize Logic Tests (no files needed)

    private let home = NSHomeDirectory()

    func testCategorizeUserPath() {
        let result = manager.categorize(
            path: "\(home)/Library/LaunchAgents/com.user.agent.plist",
            label: "com.user.agent",
            prefixes: ["com.apple."]
        )
        XCTAssertEqual(result, .user)
    }

    func testCategorizeSystemApple() {
        let result = manager.categorize(
            path: "/Library/LaunchDaemons/com.apple.test.plist",
            label: "com.apple.test",
            prefixes: ["com.apple."]
        )
        XCTAssertEqual(result, .system)
    }

    func testCategorizeThirdParty() {
        let result = manager.categorize(
            path: "/Library/LaunchAgents/com.adguard.agent.plist",
            label: "com.adguard.agent",
            prefixes: ["com.apple."]
        )
        XCTAssertEqual(result, .thirdParty)
    }

    func testCategorizeUserTakesPrecedenceOverLabel() {
        let result = manager.categorize(
            path: "\(home)/Library/LaunchAgents/com.apple.Safari.plist",
            label: "com.apple.Safari",
            prefixes: ["com.apple."]
        )
        XCTAssertEqual(result, .user)
    }

    func testCategorizeCustomVendor() {
        let result = manager.categorize(
            path: "/Library/LaunchDaemons/com.custom.vendor.plist",
            label: "com.custom.vendor",
            prefixes: ["com.apple.", "com.custom."]
        )
        XCTAssertEqual(result, .system)
    }

    // MARK: - Vendor Prefix Tests

    func testVendorPrefixesDefault() async {
        let prefixes = await manager.systemVendorPrefixes
        XCTAssertEqual(prefixes, ["com.apple."])
    }

    func testAddVendorPrefix() async {
        await manager.addVendorPrefix("com.microsoft.")

        let prefixes = await manager.systemVendorPrefixes
        XCTAssertTrue(prefixes.contains("com.microsoft."))
    }

    func testRemoveVendorPrefix() async {
        await manager.addVendorPrefix("com.test.")
        await manager.removeVendorPrefix("com.test.")

        let prefixes = await manager.systemVendorPrefixes
        XCTAssertFalse(prefixes.contains("com.test."))
    }

    func testSetVendorPrefixes() async {
        await manager.setSystemVendorPrefixes(["com.apple.", "com.custom."])

        let prefixes = await manager.systemVendorPrefixes
        XCTAssertEqual(prefixes, ["com.apple.", "com.custom."])
    }

    func testAddVendorPrefixNoDuplicates() async {
        await manager.addVendorPrefix("com.apple.")
        await manager.addVendorPrefix("com.apple.")

        let prefixes = await manager.systemVendorPrefixes
        let appleCount = prefixes.filter { $0 == "com.apple." }.count
        XCTAssertEqual(appleCount, 1)
    }
}
