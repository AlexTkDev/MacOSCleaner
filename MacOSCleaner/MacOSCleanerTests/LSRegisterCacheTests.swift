import XCTest
@testable import MacOSCleaner

final class LSRegisterCacheTests: XCTestCase {
    var tempFile: URL!

    override func setUp() {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("LSRegisterCacheTest_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFile)
    }

    func test_setAndGet() async {
        let cache = LSRegisterCache()
        await cache.set(bundleID: "com.test.app", url: tempFile)
        let retrieved = await cache.get(bundleID: "com.test.app")
        XCTAssertEqual(retrieved?.resolvingSymlinksInPath(), tempFile.resolvingSymlinksInPath())
    }

    func test_get_unknownReturnsNil() async {
        let cache = LSRegisterCache()
        let result = await cache.get(bundleID: "com.nonexistent.app")
        XCTAssertNil(result)
    }

    func test_warmup_doesNotCrash() async {
        let cache = LSRegisterCache()
        await cache.warmup()
    }

    func test_warmup_twiceNoCrash() async {
        let cache = LSRegisterCache()
        await cache.warmup()
        await cache.warmup()
    }
}
