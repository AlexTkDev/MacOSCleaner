import AppIntents
import Foundation

public struct MacOSCleanerShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanDeveloperCachesIntent(),
            phrases: [
                "Clean developer caches in \(.applicationName)",
                "Clean DerivedData with \(.applicationName)",
                "Очисти кэши разработчика в \(.applicationName)",
                "Очисти DerivedData в \(.applicationName)"
            ],
            shortTitle: "Clean Developer Caches",
            systemImageName: "hammer.fill"
        )
        AppShortcut(
            intent: GetStorageStatusIntent(),
            phrases: [
                "Get storage status in \(.applicationName)",
                "How much free space in \(.applicationName)",
                "Состояние диска в \(.applicationName)",
                "Сколько свободного места в \(.applicationName)"
            ],
            shortTitle: "Storage Status",
            systemImageName: "internaldrive.fill"
        )
        AppShortcut(
            intent: CleanCategoryIntent(),
            phrases: [
                "Clean files in \(.applicationName)",
                "Clear caches in \(.applicationName)",
                "Очисти файлы в \(.applicationName)"
            ],
            shortTitle: "Clean Files",
            systemImageName: "trash.fill"
        )
    }
}
