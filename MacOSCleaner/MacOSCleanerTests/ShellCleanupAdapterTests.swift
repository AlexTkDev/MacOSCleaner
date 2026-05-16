import XCTest
@testable import MacOSCleaner

final class ShellCleanupAdapterTests: XCTestCase {
    var commandRunner: CommandRunner!
    var adapter: ShellCleanupAdapter!
    var mockScriptPath: String!
    
    override func setUp() {
        super.setUp()
        commandRunner = CommandRunner()
        
        // Создаем mock-скрипт во временной директории
        mockScriptPath = NSTemporaryDirectory() + "mock-cleanup-\(UUID().uuidString).sh"
        let script = """
        #!/bin/bash
        echo '{"type": "step", "current": 1, "total": 2, "title": "Test Step"}'
        echo '{"type": "preview", "label": "Test Preview", "size": 100}'
        echo '{"type": "result", "label": "Test Result", "freed": 50}'
        """
        try! script.write(toFile: mockScriptPath, atomically: true, encoding: .utf8)
        chmod(mockScriptPath, 0o755)
        
        adapter = ShellCleanupAdapter(commandRunner: commandRunner, scriptPath: mockScriptPath)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: mockScriptPath)
        super.tearDown()
    }
    
    func testRunCleanupParsing() async throws {
        var events: [ShellCleanupAdapter.CleanupEvent] = []
        
        let stream = adapter.runCleanup(dryRun: true)
        for try await event in stream {
            events.append(event)
        }
        
        XCTAssertEqual(events.count, 3)
        
        // Проверка первого события
        switch events[0] {
        case .step(let current, let total, let title):
            XCTAssertEqual(current, 1)
            XCTAssertEqual(total, 2)
            XCTAssertEqual(title, "Test Step")
        default:
            XCTFail("First event should be a step")
        }
        
        // Проверка второго события
        switch events[1] {
        case .preview(let label, let size):
            XCTAssertEqual(label, "Test Preview")
            XCTAssertEqual(size, 100)
        default:
            XCTFail("Second event should be a preview")
        }
        
        // Проверка третьего события
        switch events[2] {
        case .result(let label, let freed):
            XCTAssertEqual(label, "Test Result")
            XCTAssertEqual(freed, 50)
        default:
            XCTFail("Third event should be a result")
        }
    }
}
