import Foundation

extension GeneratedCleanupPaths {
    /// `purpose: user_content` paths for local AI / LLM / ML model stores.
    /// Shown in cleanup as opt-in only — never auto-selected.
    public static func aiUserContentTemplates() -> [String] {
        var templates = Set<String>()
        for app in registry.values {
            for entry in app.paths where entry.purpose == .userContent {
                if Self.isAIRelatedTemplate(entry.template) {
                    templates.insert(entry.template)
                }
            }
        }
        for app in toolchains.values {
            for entry in app.paths where entry.purpose == .userContent {
                if Self.isAIRelatedTemplate(entry.template) {
                    templates.insert(entry.template)
                }
            }
        }
        // Extra well-known model roots not always present as user_content in SoT.
        templates.insert("<HOME>/.local/share/ollama/models")
        templates.insert("<HOME>/.ollama/models") // macOS default via Ollama.app installer
        return templates.sorted()
    }

    private static func isAIRelatedTemplate(_ template: String) -> Bool {
        let lower = template.lowercased()
        let keys = [
            "ollama", "huggingface", "lm studio", "lm-studio", "/jan", "mlx",
            "torch", "whisper", "vllm", "kagglehub", "llama", "stable-diffusion",
            "diffusionbee", "draw-things", "draw things", "ggml", "gguf",
        ]
        return keys.contains { lower.contains($0) }
    }
}
