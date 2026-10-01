import XCTest
import FoundationModels
@testable import MacOSCleaner

final class AIExplanationServiceTests: XCTestCase {
    
    func testAvailabilityCheck() async {
        let isAvailable = await AIExplanationService.shared.isAvailable
        let systemLocale = Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
        let expected = SystemLanguageModel.default.availability == .available && SystemLanguageModel.default.supportsLocale(systemLocale)
        XCTAssertEqual(isAvailable, expected)
    }

    func testAvailabilityState() async {
        let state = await AIExplanationService.shared.availabilityState
        let isAvailable = await AIExplanationService.shared.isAvailable
        XCTAssertEqual(state.isAvailable, isAvailable)
        XCTAssertFalse(state.helpTooltip.isEmpty)
    }

    func testPrewarm() async {
        // Should not throw or crash
        await AIExplanationService.shared.prewarm(promptPrefix: "Test")
    }

    func testVerdictExtraction() {
        let safeResult = AIExplanationResult.extractVerdict(from: "[SAFE] This cache is temporary and safe to delete.")
        XCTAssertEqual(safeResult.verdict, .safe)
        XCTAssertEqual(safeResult.cleanText, "This cache is temporary and safe to delete.")

        let cautionResult = AIExplanationResult.extractVerdict(from: "[CAUTION] This file contains user preferences.")
        XCTAssertEqual(cautionResult.verdict, .caution)
        XCTAssertEqual(cautionResult.cleanText, "This file contains user preferences.")

        let dangerResult = AIExplanationResult.extractVerdict(from: "[DANGER] Core system launch daemon.")
        XCTAssertEqual(dangerResult.verdict, .danger)
        XCTAssertEqual(dangerResult.cleanText, "Core system launch daemon.")

        let plainResult = AIExplanationResult.extractVerdict(from: "Plain text explanation without verdict tag.")
        XCTAssertNil(plainResult.verdict)
        XCTAssertEqual(plainResult.cleanText, "Plain text explanation without verdict tag.")
    }

    func testAIErrorDescriptions() {
        let notAvailable = AIError.notAvailable
        XCTAssertEqual(notAvailable.errorDescription, "AI model is not available on this device")

        let contextExceeded = AIError.contextSizeExceeded
        XCTAssertEqual(contextExceeded.errorDescription, "Prompt context size exceeded limit")

        let genFailed = AIError.generationFailed("Model timed out")
        XCTAssertEqual(genFailed.errorDescription, "Failed to generate explanation: Model timed out")
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
