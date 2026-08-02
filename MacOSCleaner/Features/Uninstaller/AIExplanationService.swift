import Foundation
import FoundationModels
import OSLog

private extension Logger {
    static let aiExplanation = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "AIExplanationService")
}

public actor AIExplanationService {
    public static let shared = AIExplanationService()
    
    private init() {}
    
    public nonisolated var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }
    
    private func targetLanguageName(for language: AppLanguage) -> String {
        switch language {
        case .english: return "English"
        case .russian: return "Russian"
        case .ukrainian: return "Ukrainian"
        case .spanish: return "Spanish"
        case .german: return "German"
        case .japanese: return "Japanese"
        case .french: return "French"
        case .chineseSimplified: return "Simplified Chinese"
        case .italian: return "Italian"
        case .portugueseBrazil: return "Brazilian Portuguese"
        }
    }
    
    private func runSession(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Logger.aiExplanation.error("AI Generation failed: \(error.localizedDescription, privacy: .public)")
            throw AIError.generationFailed(error.localizedDescription)
        }
    }
    
    public func explainRelation(
        appName: String,
        filePath: String,
        evidence: [String],
        deletionRisk: String,
        language: AppLanguage
    ) async throws -> String {
        guard isAvailable else { throw AIError.notAvailable }
        
        let targetLanguage = targetLanguageName(for: language)
        let instructions = "You are Antigravity AI, a macOS cleanup expert. Explain briefly (1-2 sentences) why this file belongs to the application and if it is safe to delete. You MUST respond in \(targetLanguage)."
        let prompt = """
        Application: \(appName)
        File Path: \(filePath)
        Evidence: \(evidence.joined(separator: ", "))
        Deletion Risk: \(deletionRisk)
        """
        
        return try await runSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainApp(
        appName: String,
        bundleID: String,
        sizeFormatted: String,
        language: AppLanguage
    ) async throws -> String {
        guard isAvailable else { throw AIError.notAvailable }
        
        let targetLanguage = targetLanguageName(for: language)
        let instructions = "You are Antigravity AI, a macOS expert. Explain briefly (1-2 sentences) what this application is, what it is typically used for, and if it is a core system application or third-party. You MUST respond in \(targetLanguage)."
        let prompt = """
        Application: \(appName)
        Bundle ID: \(bundleID)
        Size: \(sizeFormatted)
        """
        
        return try await runSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainStartupService(
        serviceName: String,
        filePath: String,
        category: String,
        isEnabled: Bool,
        language: AppLanguage
    ) async throws -> String {
        guard isAvailable else { throw AIError.notAvailable }
        
        let targetLanguage = targetLanguageName(for: language)
        let instructions = "You are Antigravity AI, a macOS optimization expert. Explain briefly (1-2 sentences) what this startup service does and if it is safe to disable. You MUST respond in \(targetLanguage)."
        let prompt = """
        Service Name: \(serviceName)
        File Path: \(filePath)
        Category: \(category)
        Is Enabled: \(isEnabled ? "Yes" : "No")
        """
        
        return try await runSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainCleanupFile(
        fileName: String,
        filePath: String,
        category: String,
        sizeFormatted: String,
        language: AppLanguage
    ) async throws -> String {
        guard isAvailable else { throw AIError.notAvailable }
        
        let targetLanguage = targetLanguageName(for: language)
        let instructions = "You are Antigravity AI, a macOS cleanup expert. Explain briefly (1-2 sentences) what this cache or temporary file/folder is, its purpose, and if it is safe to delete. You MUST respond in \(targetLanguage)."
        let prompt = """
        Item Name: \(fileName)
        Path: \(filePath)
        Category: \(category)
        Size: \(sizeFormatted)
        """
        
        return try await runSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainProcess(
        processName: String,
        pid: Int32,
        filePath: String,
        cpuPercent: Double,
        memoryFormatted: String,
        uptimeFormatted: String,
        language: AppLanguage
    ) async throws -> String {
        guard isAvailable else { throw AIError.notAvailable }
        
        let targetLanguage = targetLanguageName(for: language)
        let instructions = "You are Antigravity AI, a macOS process optimization expert. Explain briefly (1-2 sentences) what this running process is, what application it belongs to, and if it is safe to terminate. You MUST respond in \(targetLanguage)."
        let prompt = """
        Process Name: \(processName)
        PID: \(pid)
        Path: \(filePath)
        CPU Usage: \(String(format: "%.1f", cpuPercent))%
        Memory: \(memoryFormatted)
        Uptime: \(uptimeFormatted)
        """
        
        return try await runSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainDiskFile(
        fileName: String,
        filePath: String,
        sizeFormatted: String,
        fileType: String,
        language: AppLanguage
    ) async throws -> String {
        guard isAvailable else { throw AIError.notAvailable }
        
        let targetLanguage = targetLanguageName(for: language)
        let instructions = "You are Antigravity AI, a macOS cleanup expert. Explain briefly (1-2 sentences) what this large file or folder is, why it might occupy space, and if it is safe to delete. You MUST respond in \(targetLanguage)."
        let prompt = """
        File/Folder Name: \(fileName)
        Path: \(filePath)
        Size: \(sizeFormatted)
        Category/Type: \(fileType)
        """
        
        return try await runSession(instructions: instructions, prompt: prompt)
    }
}

public enum AIError: Error, LocalizedError {
    case notAvailable
    case generationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "AI model is not available on this device"
        case .generationFailed(let message):
            return "Failed to generate explanation: \(message)"
        }
    }
}
