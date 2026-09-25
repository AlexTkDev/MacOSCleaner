import Foundation
import FoundationModels
import OSLog
import SwiftUI

private extension Logger {
    static let aiExplanation = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "AIExplanationService")
}

@Generable
public struct AIExplanationResult: Sendable {
    @Generable
    public enum Verdict: String, Sendable {
        case safe
        case caution
        case danger
    }
    public var verdict: Verdict?
    public var explanation: String

    public init(verdict: Verdict? = nil, explanation: String) {
        self.verdict = verdict
        self.explanation = explanation
    }

    public static func extractVerdict(from text: String) -> (verdict: Verdict?, cleanText: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[SAFE]") {
            let clean = trimmed.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
            return (.safe, clean)
        } else if trimmed.hasPrefix("[CAUTION]") {
            let clean = trimmed.dropFirst(9).trimmingCharacters(in: .whitespacesAndNewlines)
            return (.caution, clean)
        } else if trimmed.hasPrefix("[DANGER]") {
            let clean = trimmed.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
            return (.danger, clean)
        }
        return (nil, trimmed)
    }
}

public enum AIAvailabilityState: Equatable, Sendable {
    case ready
    case unsupportedDevice
    case notEnabledInSettings
    case modelPreparing
    case unsupportedLanguage

    public var isAvailable: Bool {
        self == .ready
    }

    public var helpTooltip: String {
        switch self {
        case .ready:
            return "uninstaller_explain_with_ai".localized
        case .unsupportedDevice:
            return "settings_ai_status_unsupported_device".localized
        case .notEnabledInSettings:
            return "settings_ai_hint_not_enabled".localized
        case .modelPreparing:
            return "settings_ai_status_preparing".localized
        case .unsupportedLanguage:
            return "settings_ai_hint_unsupported_language".localized
        }
    }
}

public actor AIExplanationService {
    public static let shared = AIExplanationService()
    
    private init() {}
    
    public nonisolated var availabilityState: AIAvailabilityState {
        let systemLocale = Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
        guard SystemLanguageModel.default.supportsLocale(systemLocale) else {
            return .unsupportedLanguage
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unsupportedDevice
            case .appleIntelligenceNotEnabled:
                return .notEnabledInSettings
            case .modelNotReady:
                return .modelPreparing
            @unknown default:
                return .unsupportedDevice
            }
        }
    }

    public nonisolated var isAvailable: Bool {
        availabilityState == .ready
    }
    
    public nonisolated func prewarm(promptPrefix: String? = nil) {
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        session.prewarm()
    }

    // MARK: - Localized Instructions via Swift switch (No "Respond in X" in instructions)
    private func instructionForRelation(language: AppLanguage) -> String {
        switch language {
        case .russian:
            return "Ты эксперт по macOS. Кратко (1-2 предложения) объясни, почему этот файл относится к приложению и безопасно ли его удалять. В начале ответа укажи вердикт: [SAFE], [CAUTION] или [DANGER]."
        case .ukrainian:
            return "Ти експерт з macOS. Коротко (1-2 речення) поясни, чому цей файл належить додатку та чи безпечно його видаляти. На початку вкажи вердикт: [SAFE], [CAUTION] або [DANGER]."
        case .german:
            return "Du bist macOS-Experte. Erkläre kurz (1-2 Sätze), warum diese Datei zur App gehört und ob das Löschen sicher ist. Gib am Anfang das Urteil an: [SAFE], [CAUTION] oder [DANGER]."
        case .french:
            return "Tu es un expert macOS. Explique brièvement (1-2 phrases) pourquoi ce fichier appartient à l'application et s'il peut être supprimé en toute sécurité. Indique au début le verdict : [SAFE], [CAUTION] ou [DANGER]."
        case .spanish:
            return "Eres un experto en macOS. Explica brevemente (1-2 frases) por qué este archivo pertenece a la aplicación y si es seguro eliminarlo. Indica al inicio el veredicto: [SAFE], [CAUTION] o [DANGER]."
        case .italian:
            return "Sei un esperto macOS. Spiega brevemente (1-2 frasi) perché questo file appartiene all'applicazione e se è sicuro rimuoverlo. Indica all'inizio il verdetto: [SAFE], [CAUTION] o [DANGER]."
        case .japanese:
            return "macOSのエキスパートとして、このファイルがアプリに関連する理由と削除しても安全かを簡潔に（1〜2文で）説明してください。冒頭に [SAFE]、[CAUTION]、または [DANGER] を記載してください。"
        case .chineseSimplified:
            return "作为 macOS 专家，简要（1-2句）说明此文件为何属于该应用以及删除是否安全。在开头标明裁决：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .chineseTraditional:
            return "作為 macOS 專家，簡要（1-2句）說明此檔案為何屬於該應用程式以及刪除是否安全。在開頭標明裁定：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .korean:
            return "macOS 전문가로서 이 파일이 앱에 속하는 이유와 삭제해도 안전한지 간단히(1~2문장) 설명해 주세요. 시작 부분에 [SAFE], [CAUTION] 또는 [DANGER]를 명시하세요."
        case .polish:
            return "Jesteś ekspertem macOS. Wyjaśnij krótko (1-2 zdania), dlaczego ten plik należy do aplikacji i czy jest bezpieczny do usunięcia. Na początku podaj werdykt: [SAFE], [CAUTION] lub [DANGER]."
        case .portugueseBrazil:
            return "Você é um especialista em macOS. Explique brevemente (1-2 frases) por que este arquivo pertence ao aplicativo e se é seguro apagá-lo. Indique no início o veredito: [SAFE], [CAUTION] ou [DANGER]."
        case .arabic:
            return "أنت خبير في macOS. اشرح بإيجاز (في جملة أو جملتين) سبب ارتباط هذا الملف بالتطبيق وما إذا كان حذفه آمنًا. اذكر الحكم في البداية: [SAFE] أو [CAUTION] أو [DANGER]."
        case .english:
            return "You are a macOS cleanup expert. Explain briefly (1-2 sentences) why this file belongs to the application and if it is safe to delete. Start your response with verdict: [SAFE], [CAUTION], or [DANGER]."
        }
    }

    private func instructionForApp(language: AppLanguage) -> String {
        switch language {
        case .russian:
            return "Ты эксперт по macOS. Кратко (1-2 предложения) объясни назначение приложения и является ли оно системным или сторонним."
        case .ukrainian:
            return "Ти експерт з macOS. Коротко (1-2 речення) поясни призначення додатку та чи є він системним або стороннім."
        case .german:
            return "Du bist macOS-Experte. Erkläre kurz (1-2 Sätze) den Zweck der Anwendung und ob es sich um eine System- oder Drittanbieter-App handelt."
        case .french:
            return "Tu es un expert macOS. Explique brièvement (1-2 phrases) le rôle de l'application et s'il s'agit d'une application système ou tierce."
        case .spanish:
            return "Eres un experto en macOS. Explica brevemente (1-2 frases) el propósito de la aplicación y si es del sistema o de terceros."
        case .italian:
            return "Sei un esperto macOS. Spiega brevemente (1-2 frasi) lo scopo dell'applicazione e se si tratta di un'app di sistema o di terze parti."
        case .japanese:
            return "macOSのエキスパートとして、このアプリケーションの目的と、システムアプリかサードパーティ製かを簡潔に（1〜2文で）説明してください。"
        case .chineseSimplified:
            return "作为 macOS 专家，简要（1-2句）说明该应用的用途，以及它是系统应用还是第三方应用。"
        case .chineseTraditional:
            return "作為 macOS 專家，簡要（1-2句）說明該應用程式的用途，以及它是系統應用程式還是第三方應用程式。"
        case .korean:
            return "macOS 전문가로서 이 애플리케이션의 용도와 시스템 앱인지 타사 앱인지 간단히(1~2문장) 설명해 주세요."
        case .polish:
            return "Jesteś ekspertem macOS. Wyjaśnij krótko (1-2 zdania) przeznaczenie aplikacji oraz czy jest to aplikacja systemowa czy innej firmy."
        case .portugueseBrazil:
            return "Você é um especialista em macOS. Explique brevemente (1-2 frases) a finalidade do aplicativo e se ele é do sistema ou de terceiros."
        case .arabic:
            return "أنت خبير في macOS. اشرح بإيجاز (في جملة أو جملتين) الغرض من التطبيق وما إذا كان تطبيق نظام أم تطبيقًا تابعًا لجهة خارجية."
        case .english:
            return "You are a macOS expert. Explain briefly (1-2 sentences) what this application is, what it is typically used for, and if it is a core system application or third-party."
        }
    }

    private func instructionForCleanup(language: AppLanguage) -> String {
        switch language {
        case .russian:
            return "Ты эксперт по очистке macOS. Кратко (1-2 предложения) объясни назначение файла/кэша и безопасность его удаления. В начале укажи вердикт: [SAFE], [CAUTION] или [DANGER]."
        case .ukrainian:
            return "Ти експерт з очищення macOS. Коротко (1-2 речення) поясни призначення файлу/кешу та безпеку його видалення. На початку вкажи вердикт: [SAFE], [CAUTION] або [DANGER]."
        case .german:
            return "Du bist macOS-Bereinigungsexperte. Erkläre kurz (1-2 Sätze) den Zweck dieser Datei/des Cache und ob das Löschen sicher ist. Gib am Anfang das Urteil an: [SAFE], [CAUTION] oder [DANGER]."
        case .french:
            return "Tu es un expert en nettoyage macOS. Explique brièvement (1-2 phrases) l'utilité de ce fichier/cache et s'il peut être supprimé en toute sécurité. Indique au début le verdict : [SAFE], [CAUTION] ou [DANGER]."
        case .spanish:
            return "Eres un experto en limpieza de macOS. Explica brevemente (1-2 frases) el propósito de este archivo/caché y si es seguro eliminarlo. Indica al inicio el veredicto: [SAFE], [CAUTION] o [DANGER]."
        case .italian:
            return "Sei un esperto di pulizia macOS. Spiega brevemente (1-2 frasi) lo scopo di questo file/cache e se è sicuro rimuoverlo. Indica all'inizio il verdetto: [SAFE], [CAUTION] o [DANGER]."
        case .japanese:
            return "macOSクリーンアップのエキスパートとして、このキャッシュ/ファイルの役割と削除の安全性を簡潔に（1〜2文で）説明してください。冒頭に [SAFE]、[CAUTION]、または [DANGER] を記載してください。"
        case .chineseSimplified:
            return "作为 macOS 清理专家，简要（1-2句）说明此缓存/文件的用途以及删除是否安全。在开头标明裁决：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .chineseTraditional:
            return "作為 macOS 清理專家，簡要（1-2句）說明此快取/檔案的用途以及刪除是否安全。在開頭標明裁定：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .korean:
            return "macOS 정리 전문가로서 이 캐시/파일의 용도와 삭제 안전성을 간단히(1~2문장) 설명해 주세요. 시작 부분에 [SAFE], [CAUTION] 또는 [DANGER]를 명시하세요."
        case .polish:
            return "Jesteś ekspertem ds. czyszczenia macOS. Wyjaśnij krótko (1-2 zdania) przeznaczenie tego pliku/pamięci podręcznej i czy usunięcie jest bezpieczne. Na początku podaj werdykt: [SAFE], [CAUTION] lub [DANGER]."
        case .portugueseBrazil:
            return "Você é um especialista em limpeza do macOS. Explique brevemente (1-2 frases) a finalidade deste arquivo/cache e se é seguro apagá-lo. Indique no início o veredito: [SAFE], [CAUTION] ou [DANGER]."
        case .arabic:
            return "أنت خبير في تنظيف macOS. اشرح بإيجاز (في جملة أو جملتين) الغرض من ملف التخزين المؤقت/الملف وأمان حذفه. اذكر الحكم في البداية: [SAFE] أو [CAUTION] أو [DANGER]."
        case .english:
            return "You are a macOS cleanup expert. Explain briefly (1-2 sentences) what this cache or temporary file is and if it is safe to delete. Start your response with verdict: [SAFE], [CAUTION], or [DANGER]."
        }
    }

    private func instructionForStartup(language: AppLanguage) -> String {
        switch language {
        case .russian:
            return "Ты эксперт по оптимизации macOS. Кратко (1-2 предложения) объясни назначение службы автозапуска и безопасность её отключения. В начале укажи вердикт: [SAFE], [CAUTION] или [DANGER]."
        case .ukrainian:
            return "Ти експерт з оптимізації macOS. Коротко (1-2 речення) поясни призначення служби автозапуску та безпеку її вимкнення. На початку вкажи вердикт: [SAFE], [CAUTION] або [DANGER]."
        case .german:
            return "Du bist macOS-Optimierungsexperte. Erkläre kurz (1-2 Sätze) die Funktion dieses Autostart-Dienstes und ob das Deaktivieren sicher ist. Gib am Anfang das Urteil an: [SAFE], [CAUTION] oder [DANGER]."
        case .french:
            return "Tu es un expert en optimisation macOS. Explique brièvement (1-2 phrases) ce que fait ce service de démarrage et si sa désactivation est sans danger. Indique au début le verdict : [SAFE], [CAUTION] ou [DANGER]."
        case .spanish:
            return "Eres un experto en optimización de macOS. Explica brevemente (1-2 frases) qué hace este servicio de inicio y si es seguro desactivarlo. Indica al inicio el veredicto: [SAFE], [CAUTION] o [DANGER]."
        case .italian:
            return "Sei un esperto di ottimizzazione macOS. Spiega brevemente (1-2 frasi) cosa fa questo servizio di avvio e se è sicuro disabilitarlo. Indica all'inizio il verdetto: [SAFE], [CAUTION] o [DANGER]."
        case .japanese:
            return "macOS最適化のエキスパートとして、このスタートアップサービスの役割と無効化の安全性を簡潔に（1〜2文で）説明してください。冒頭に [SAFE]、[CAUTION]、または [DANGER] を記載してください。"
        case .chineseSimplified:
            return "作为 macOS 优化专家，简要（1-2句）说明此启动项的作用以及禁用是否安全。在开头标明裁决：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .chineseTraditional:
            return "作為 macOS 最佳化專家，簡要（1-2句）說明此啟動項目的用途以及停用是否安全。在開頭標明裁定：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .korean:
            return "macOS 최적화 전문가로서 이 시작 서비스의 기능과 비활성화 안전성을 간단히(1~2문장) 설명해 주세요. 시작 부분에 [SAFE], [CAUTION] 또는 [DANGER]를 명시하세요."
        case .polish:
            return "Jesteś ekspertem ds. optymalizacji macOS. Wyjaśnij krótko (1-2 zdania), co robi ta usługa startowa i czy jej wyłączenie jest bezpieczne. Na początku podaj werdykt: [SAFE], [CAUTION] lub [DANGER]."
        case .portugueseBrazil:
            return "Você é um especialista em otimização do macOS. Explique brevemente (1-2 frases) o que este serviço de inicialização faz e se é seguro desativá-lo. Indique no início o veredito: [SAFE], [CAUTION] ou [DANGER]."
        case .arabic:
            return "أنت خبير في تحسين نظام macOS. اشرح بإيجاز (في جملة أو جملتين) ما تفعله خدمة بدء التشغيل هذه وأمان تعطيلها. اذكر الحكم في البداية: [SAFE] أو [CAUTION] أو [DANGER]."
        case .english:
            return "You are a macOS optimization expert. Explain briefly (1-2 sentences) what this startup service does and if it is safe to disable. Start your response with verdict: [SAFE], [CAUTION], or [DANGER]."
        }
    }

    private func instructionForProcess(language: AppLanguage) -> String {
        switch language {
        case .russian:
            return "Ты эксперт по процессам macOS. Кратко (1-2 предложения) объясни назначение процесса и безопасность его завершения. В начале укажи вердикт: [SAFE], [CAUTION] или [DANGER]."
        case .ukrainian:
            return "Ти експерт з процесів macOS. Коротко (1-2 речення) поясни призначення процесу та безпеку його завершення. На початку вкажи вердикт: [SAFE], [CAUTION] або [DANGER]."
        case .german:
            return "Du bist macOS-Prozessexperte. Erkläre kurz (1-2 Sätze) den Zweck dieses Prozesses und ob das Beenden sicher ist. Gib am Anfang das Urteil an: [SAFE], [CAUTION] oder [DANGER]."
        case .french:
            return "Tu es un expert des processus macOS. Explique brièvement (1-2 phrases) ce que fait ce processus et si son arrêt est sans danger. Indique au début le verdict : [SAFE], [CAUTION] ou [DANGER]."
        case .spanish:
            return "Eres un experto en procesos de macOS. Explica brevemente (1-2 frases) qué hace este proceso y si es seguro finalizarlo. Indica al inicio el veredicto: [SAFE], [CAUTION] o [DANGER]."
        case .italian:
            return "Sei un esperto di processi macOS. Spiega brevemente (1-2 frasi) cosa fa questo processo e se è sicuro terminarlo. Indica all'inizio il verdetto: [SAFE], [CAUTION] o [DANGER]."
        case .japanese:
            return "macOSプロセスのエキスパートとして、この実行中プロセスの役割と終了の安全性を簡潔に（1〜2文で）説明してください。冒頭に [SAFE]、[CAUTION]、または [DANGER] を記載してください。"
        case .chineseSimplified:
            return "作为 macOS 进程优化专家，简要（1-2句）说明此运行进程的作用以及终止是否安全。在开头标明裁决：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .chineseTraditional:
            return "作為 macOS 行程專家，簡要（1-2句）說明此運行中行程的用途以及終止是否安全。在開頭標明裁定：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .korean:
            return "macOS 프로세스 전문가로서 이 실행 중인 프로세스의 역할과 종료 안전성을 간단히(1~2문장) 설명해 주세요. 시작 부분에 [SAFE], [CAUTION] 또는 [DANGER]를 명시하세요."
        case .polish:
            return "Jesteś ekspertem od procesów macOS. Wyjaśnij krótko (1-2 zdania), czym jest ten proces i czy jego zakończenie jest bezpieczne. Na początku podaj werdykt: [SAFE], [CAUTION] lub [DANGER]."
        case .portugueseBrazil:
            return "Você é um especialista em processos do macOS. Explique brevemente (1-2 frases) o que este processo faz e se é seguro encerrá-lo. Indique no início o veredito: [SAFE], [CAUTION] ou [DANGER]."
        case .arabic:
            return "أنت خبير في عمليات نظام macOS. اشرح بإيجاز (في جملة أو جملتين) ما تفعله هذه العملية الجارية وأمان إنهائها. اذكر الحكم في البداية: [SAFE] أو [CAUTION] أو [DANGER]."
        case .english:
            return "You are a macOS process expert. Explain briefly (1-2 sentences) what this process is and if it is safe to terminate. Start your response with verdict: [SAFE], [CAUTION], or [DANGER]."
        }
    }

    private func instructionForDisk(language: AppLanguage) -> String {
        switch language {
        case .russian:
            return "Ты эксперт по очистке macOS. Кратко (1-2 предложения) объясни назначение этого большого файла/папки и безопасность его удаления. В начале укажи вердикт: [SAFE], [CAUTION] или [DANGER]."
        case .ukrainian:
            return "Ти експерт з очищення macOS. Коротко (1-2 речення) поясни призначення цього великого файлу/папки та безпеку його видалення. На початку вкажи вердикт: [SAFE], [CAUTION] або [DANGER]."
        case .german:
            return "Du bist macOS-Bereinigungsexperte. Erkläre kurz (1-2 Sätze) die Bedeutung dieser großen Datei/dieses Ordners und ob das Löschen sicher ist. Gib am Anfang das Urteil an: [SAFE], [CAUTION] oder [DANGER]."
        case .french:
            return "Tu es un expert macOS. Explique brièvement (1-2 phrases) ce qu'est ce gros fichier/dossier et s'il est sûr de le supprimer. Indique au début le verdict : [SAFE], [CAUTION] ou [DANGER]."
        case .spanish:
            return "Eres un experto en macOS. Explica brevemente (1-2 frases) qué es este archivo o carpeta grande y si es seguro eliminarlo. Indica al inicio el veredicto: [SAFE], [CAUTION] o [DANGER]."
        case .italian:
            return "Sei un esperto macOS. Spiega brevemente (1-2 frasi) cosa rappresenta questo file o cartella di grandi dimensioni e se è sicuro eliminarlo. Indica all'inizio il verdetto: [SAFE], [CAUTION] o [DANGER]."
        case .japanese:
            return "macOSクリーンアップのエキスパートとして、この大容量ファイル/フォルダの役割と削除の安全性を簡潔に（1〜2文で）説明してください。冒頭に [SAFE]、[CAUTION]、または [DANGER] を記載してください。"
        case .chineseSimplified:
            return "作为 macOS 清理专家，简要（1-2句）说明此大文件/文件夹的用途以及删除是否安全。在开头标明裁决：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .chineseTraditional:
            return "作為 macOS 清理專家，簡要（1-2句）說明此大檔案/資料夾的用途以及刪除是否安全。在開頭標明裁定：[SAFE]、[CAUTION] 或 [DANGER]。"
        case .korean:
            return "macOS 정리 전문가로서 이 대용량 파일/폴더의 용도와 삭제 안전성을 간단히(1~2문장) 설명해 주세요. 시작 부분에 [SAFE], [CAUTION] 또는 [DANGER]를 명시하세요."
        case .polish:
            return "Jesteś ekspertem ds. czyszczenia macOS. Wyjaśnij krótko (1-2 zdania), czym jest ten duży plik/katalog i czy jego usunięcie jest bezpieczne. Na początku podaj werdykt: [SAFE], [CAUTION] lub [DANGER]."
        case .portugueseBrazil:
            return "Você é um especialista em macOS. Explique brevemente (1-2 frases) o que é este arquivo ou pasta grande e se é seguro apagá-lo. Indique no início o veredito: [SAFE], [CAUTION] ou [DANGER]."
        case .arabic:
            return "أنت خبير في تنظيف macOS. اشرح بإيجاز (في جملة أو جملتين) ما يمثله هذا الملف أو المجلد الكبير وأمان حذفه. اذكر الحكم في البداية: [SAFE] أو [CAUTION] أو [DANGER]."
        case .english:
            return "You are a macOS cleanup expert. Explain briefly (1-2 sentences) what this large file or folder is and if it is safe to delete. Start your response with verdict: [SAFE], [CAUTION], or [DANGER]."
        }
    }

    // MARK: - Context Size Check & Heuristic
    private func checkContextSize(prompt: String, instructions: String) async throws {
        let maxSize = SystemLanguageModel.default.contextSize ?? 4096
        
        if #available(macOS 26.4, *) {
            let promptCount = try await SystemLanguageModel.default.tokenCount(for: prompt)
            let instructionCount = try await SystemLanguageModel.default.tokenCount(for: Instructions(instructions))
            if promptCount + instructionCount > maxSize {
                Logger.aiExplanation.warning("Context size exceeded limit: \(promptCount + instructionCount) > \(maxSize)")
                throw AIError.contextSizeExceeded
            }
        } else {
            // Conservative heuristic: average 2.5 characters per token for mixed Cyrillic/paths
            let estimatedTokens = Double(prompt.count + instructions.count) / 2.5
            if estimatedTokens > Double(maxSize) {
                Logger.aiExplanation.warning("Context size exceeded heuristic limit: chars=\(prompt.count + instructions.count)")
                throw AIError.contextSizeExceeded
            }
        }
    }
    
    // MARK: - Session Execution
    private func runSession(instructions: String, prompt: String) async throws -> AIExplanationResult {
        let session = LanguageModelSession(instructions: instructions)
        try await checkContextSize(prompt: prompt, instructions: instructions)
        
        do {
            let response = try await session.respond(to: prompt, generating: AIExplanationResult.self)
            if #available(macOS 27.0, *) {
                Logger.aiExplanation.info("Session structured completed. Usage: \(String(describing: session.usage), privacy: .public)")
            }
            return response.content
        } catch {
            Logger.aiExplanation.warning("Structured generation failed, falling back to text: \(error.localizedDescription, privacy: .public)")
            do {
                let response = try await session.respond(to: prompt)
                if #available(macOS 27.0, *) {
                    Logger.aiExplanation.info("Session text fallback completed. Usage: \(String(describing: session.usage), privacy: .public)")
                }
                let (extractedVerdict, clean) = AIExplanationResult.extractVerdict(from: response.content)
                return AIExplanationResult(verdict: extractedVerdict, explanation: clean.isEmpty ? response.content : clean)
            } catch {
                Logger.aiExplanation.error("AI Generation failed: \(error.localizedDescription, privacy: .public)")
                throw AIError.generationFailed(error.localizedDescription)
            }
        }
    }
    
    public func streamSession(instructions: String, prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        try await checkContextSize(prompt: prompt, instructions: instructions)
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let innerStream = session.streamResponse(to: prompt)
                    for try await chunk in innerStream {
                        continuation.yield(chunk.content)
                    }
                    if #available(macOS 27.0, *) {
                        Logger.aiExplanation.info("Stream completed. Usage: \(String(describing: session.usage), privacy: .public)")
                    }
                    continuation.finish()
                } catch {
                    Logger.aiExplanation.error("Stream failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    // MARK: - Feature Explain APIs
    public func explainRelation(
        appName: String,
        filePath: String,
        evidence: [String],
        deletionRisk: String,
        language: AppLanguage
    ) async throws -> AIExplanationResult {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForRelation(language: language)
        let prompt = """
        Application: \(appName)
        File Path: \(String(filePath.prefix(1500)))
        Evidence: \(evidence.joined(separator: ", "))
        Deletion Risk: \(deletionRisk)
        """
        return try await runSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainRelationStream(
        appName: String,
        filePath: String,
        evidence: [String],
        deletionRisk: String,
        language: AppLanguage
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForRelation(language: language)
        let prompt = """
        Application: \(appName)
        File Path: \(String(filePath.prefix(1500)))
        Evidence: \(evidence.joined(separator: ", "))
        Deletion Risk: \(deletionRisk)
        """
        return try await streamSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainApp(
        appName: String,
        bundleID: String,
        sizeFormatted: String,
        language: AppLanguage
    ) async throws -> AIExplanationResult {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForApp(language: language)
        let prompt = """
        Application: \(appName)
        Bundle ID: \(bundleID)
        Size: \(sizeFormatted)
        """
        return try await runSession(instructions: instructions, prompt: prompt)
    }

    public func explainAppStream(
        appName: String,
        bundleID: String,
        sizeFormatted: String,
        language: AppLanguage
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForApp(language: language)
        let prompt = """
        Application: \(appName)
        Bundle ID: \(bundleID)
        Size: \(sizeFormatted)
        """
        return try await streamSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainStartupService(
        serviceName: String,
        filePath: String,
        category: String,
        isEnabled: Bool,
        language: AppLanguage
    ) async throws -> AIExplanationResult {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForStartup(language: language)
        let prompt = """
        Service Name: \(serviceName)
        File Path: \(String(filePath.prefix(1500)))
        Category: \(category)
        Is Enabled: \(isEnabled ? "Yes" : "No")
        """
        return try await runSession(instructions: instructions, prompt: prompt)
    }

    public func explainStartupServiceStream(
        serviceName: String,
        filePath: String,
        category: String,
        isEnabled: Bool,
        language: AppLanguage
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForStartup(language: language)
        let prompt = """
        Service Name: \(serviceName)
        File Path: \(String(filePath.prefix(1500)))
        Category: \(category)
        Is Enabled: \(isEnabled ? "Yes" : "No")
        """
        return try await streamSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainCleanupFile(
        fileName: String,
        filePath: String,
        category: String,
        sizeFormatted: String,
        language: AppLanguage
    ) async throws -> AIExplanationResult {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForCleanup(language: language)
        let prompt = """
        Item Name: \(fileName)
        Path: \(String(filePath.prefix(1500)))
        Category: \(category)
        Size: \(sizeFormatted)
        """
        return try await runSession(instructions: instructions, prompt: prompt)
    }

    public func explainCleanupFileStream(
        fileName: String,
        filePath: String,
        category: String,
        sizeFormatted: String,
        language: AppLanguage
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForCleanup(language: language)
        let prompt = """
        Item Name: \(fileName)
        Path: \(String(filePath.prefix(1500)))
        Category: \(category)
        Size: \(sizeFormatted)
        """
        return try await streamSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainProcess(
        processName: String,
        pid: Int32,
        filePath: String,
        cpuPercent: Double,
        memoryFormatted: String,
        uptimeFormatted: String,
        language: AppLanguage
    ) async throws -> AIExplanationResult {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForProcess(language: language)
        let prompt = """
        Process Name: \(processName)
        PID: \(pid)
        Path: \(String(filePath.prefix(1500)))
        CPU Usage: \(String(format: "%.1f", cpuPercent))%
        Memory: \(memoryFormatted)
        Uptime: \(uptimeFormatted)
        """
        return try await runSession(instructions: instructions, prompt: prompt)
    }

    public func explainProcessStream(
        processName: String,
        pid: Int32,
        filePath: String,
        cpuPercent: Double,
        memoryFormatted: String,
        uptimeFormatted: String,
        language: AppLanguage
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForProcess(language: language)
        let prompt = """
        Process Name: \(processName)
        PID: \(pid)
        Path: \(String(filePath.prefix(1500)))
        CPU Usage: \(String(format: "%.1f", cpuPercent))%
        Memory: \(memoryFormatted)
        Uptime: \(uptimeFormatted)
        """
        return try await streamSession(instructions: instructions, prompt: prompt)
    }
    
    public func explainDiskFile(
        fileName: String,
        filePath: String,
        sizeFormatted: String,
        fileType: String,
        language: AppLanguage
    ) async throws -> AIExplanationResult {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForDisk(language: language)
        let prompt = """
        File/Folder Name: \(fileName)
        Path: \(String(filePath.prefix(1500)))
        Size: \(sizeFormatted)
        Category/Type: \(fileType)
        """
        return try await runSession(instructions: instructions, prompt: prompt)
    }

    public func explainDiskFileStream(
        fileName: String,
        filePath: String,
        sizeFormatted: String,
        fileType: String,
        language: AppLanguage
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard isAvailable else { throw AIError.notAvailable }
        let instructions = instructionForDisk(language: language)
        let prompt = """
        File/Folder Name: \(fileName)
        Path: \(String(filePath.prefix(1500)))
        Size: \(sizeFormatted)
        Category/Type: \(fileType)
        """
        return try await streamSession(instructions: instructions, prompt: prompt)
    }
}

public enum AIError: Error, LocalizedError, Equatable, Sendable {
    case notAvailable
    case contextSizeExceeded
    case generationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "AI model is not available on this device"
        case .contextSizeExceeded:
            return "Prompt context size exceeded limit"
        case .generationFailed(let message):
            return "Failed to generate explanation: \(message)"
        }
    }
}

// MARK: - Reusable UI Components for Apple Intelligence

public struct AIExplainButton: View {
    public let isExpanded: Bool
    public let isEnabledSetting: Bool
    public let action: () -> Void
    
    public init(isExpanded: Bool, isEnabledSetting: Bool, action: @escaping () -> Void) {
        self.isExpanded = isExpanded
        self.isEnabledSetting = isEnabledSetting
        self.action = action
    }
    
    private var state: AIAvailabilityState {
        AIExplanationService.shared.availabilityState
    }
    
    public var body: some View {
        if isEnabledSetting {
            switch state {
            case .unsupportedDevice:
                EmptyView()
            case .notEnabledInSettings:
                Button {} label: {
                    Image(systemName: "sparkles")
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("settings_ai_hint_not_enabled".localized)
            case .modelPreparing:
                Button {} label: {
                    Image(systemName: "sparkles")
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("settings_ai_status_preparing".localized)
            case .unsupportedLanguage:
                Button {} label: {
                    Image(systemName: "sparkles")
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("settings_ai_hint_unsupported_language".localized)
            case .ready:
                Button(action: action) {
                    Image(systemName: "sparkles")
                        .foregroundColor(isExpanded ? .purple : .secondary)
                }
                .buttonStyle(.plain)
                .help("uninstaller_explain_with_ai".localized)
            }
        }
    }
}

public struct AIVerdictBadge: View {
    public let verdict: AIExplanationResult.Verdict
    
    public init(verdict: AIExplanationResult.Verdict) {
        self.verdict = verdict
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .bold))
            Text(title)
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.15)))
    }
    
    private var title: String {
        switch verdict {
        case .safe: return "SAFE"
        case .caution: return "CAUTION"
        case .danger: return "DANGER"
        }
    }
    
    private var color: Color {
        switch verdict {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        }
    }
    
    private var iconName: String {
        switch verdict {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.shield.fill"
        }
    }
}
