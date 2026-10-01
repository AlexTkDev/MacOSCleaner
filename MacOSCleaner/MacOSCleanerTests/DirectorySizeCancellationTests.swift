import XCTest
@testable import MacOSCleaner

final class DirectorySizeCancellationTests: XCTestCase {
    func testCancelledDirectorySizeIsNotCached() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("size-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("blob")
        try Data(count: 4096).write(to: file)

        let cancelled = Task.detached {
            while !Task.isCancelled {
                await Task.yield()
            }
            return FileManager.default.getDirectorySize(url: root)
        }
        cancelled.cancel()
        _ = await cancelled.value

        let measured = FileManager.default.getDirectorySize(url: root)
        XCTAssertGreaterThan(measured, 0)
    }
}
