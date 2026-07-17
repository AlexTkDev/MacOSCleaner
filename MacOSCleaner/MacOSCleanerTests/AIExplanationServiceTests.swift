import XCTest
import FoundationModels
@testable import MacOSCleaner

final class AIExplanationServiceTests: XCTestCase {
    
    func testAvailabilityCheck() async {
        let isAvailable = await AIExplanationService.shared.isAvailable
        // Since we are running in a test suite, we check if availability returns the expected boolean
        XCTAssertEqual(isAvailable, SystemLanguageModel.default.availability == .available)
    }
    
    func testUnavailableThrowsError() async {
        let isAvailable = await AIExplanationService.shared.isAvailable
        if !isAvailable {
            // Test explainRelation
            do {
                _ = try await AIExplanationService.shared.explainRelation(
                    appName: "TestApp",
                    filePath: "/tmp/test",
                    evidence: ["Test evidence"],
                    deletionRisk: "safe",
                    language: .english
                )
                XCTFail("Should have thrown an error")
            } catch let error as AIError {
                XCTAssertEqual(error.localizedDescription, AIError.notAvailable.localizedDescription)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            // Test explainStartupService
            do {
                _ = try await AIExplanationService.shared.explainStartupService(
                    serviceName: "com.test.agent",
                    filePath: "/Library/LaunchAgents/com.test.agent.plist",
                    category: "system",
                    isEnabled: true,
                    language: .english
                )
                XCTFail("Should have thrown an error")
            } catch let error as AIError {
                XCTAssertEqual(error.localizedDescription, AIError.notAvailable.localizedDescription)
            } catch {
                XCTFail("Unexpected error")
            }

            // Test explainCleanupFile
            do {
                _ = try await AIExplanationService.shared.explainCleanupFile(
                    fileName: "Cache.db",
                    filePath: "/Users/test/Library/Caches/Cache.db",
                    category: "Caches",
                    sizeFormatted: "12 MB",
                    language: .english
                )
                XCTFail("Should have thrown an error")
            } catch let error as AIError {
                XCTAssertEqual(error.localizedDescription, AIError.notAvailable.localizedDescription)
            } catch {
                XCTFail("Unexpected error")
            }

            // Test explainProcess
            do {
                _ = try await AIExplanationService.shared.explainProcess(
                    processName: "testproc",
                    pid: 1234,
                    filePath: "/usr/local/bin/testproc",
                    cpuPercent: 1.5,
                    memoryFormatted: "45 MB",
                    uptimeFormatted: "10m",
                    language: .english
                )
                XCTFail("Should have thrown an error")
            } catch let error as AIError {
                XCTAssertEqual(error.localizedDescription, AIError.notAvailable.localizedDescription)
            } catch {
                XCTFail("Unexpected error")
            }

            // Test explainDiskFile
            do {
                _ = try await AIExplanationService.shared.explainDiskFile(
                    fileName: "Movie.mp4",
                    filePath: "/Users/test/Movies/Movie.mp4",
                    sizeFormatted: "1.2 GB",
                    fileType: "Video",
                    language: .english
                )
                XCTFail("Should have thrown an error")
            } catch let error as AIError {
                XCTAssertEqual(error.localizedDescription, AIError.notAvailable.localizedDescription)
            } catch {
                XCTFail("Unexpected error")
            }
            
            // Test explainApp
            do {
                _ = try await AIExplanationService.shared.explainApp(
                    appName: "TestApp",
                    bundleID: "com.test.app",
                    sizeFormatted: "150 MB",
                    language: .english
                )
                XCTFail("Should have thrown an error")
            } catch let error as AIError {
                XCTAssertEqual(error.localizedDescription, AIError.notAvailable.localizedDescription)
            } catch {
                XCTFail("Unexpected error")
            }
        }
    }
}
