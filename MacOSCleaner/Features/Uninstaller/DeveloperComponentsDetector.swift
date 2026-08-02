import Foundation

public enum DeveloperComponentsDetector {
    public struct DeveloperPathEntry: Sendable {
        public let titleKey: String
        public let fallbackTitle: String
        public let category: CleanupCategory
        public let relativeHomePath: String?
        public let absolutePath: String?
        public let isSelected: Bool
        public let matchesApp: @Sendable (_ appNameLower: String, _ bundleIDLower: String) -> Bool

        public init(
            titleKey: String,
            fallbackTitle: String,
            category: CleanupCategory,
            relativeHomePath: String? = nil,
            absolutePath: String? = nil,
            isSelected: Bool = false,
            matchesApp: @escaping @Sendable (_ appNameLower: String, _ bundleIDLower: String) -> Bool
        ) {
            self.titleKey = titleKey
            self.fallbackTitle = fallbackTitle
            self.category = category
            self.relativeHomePath = relativeHomePath
            self.absolutePath = absolutePath
            self.isSelected = isSelected
            self.matchesApp = matchesApp
        }
    }

    /// Static Path Map for application-specific developer components.
    public static let pathMap: [DeveloperPathEntry] = [
        // Xcode (mark all by default)
        DeveloperPathEntry(
            titleKey: "developer.xcode_derived_data", fallbackTitle: "Xcode DerivedData",
            category: .xcode, relativeHomePath: "Library/Developer/Xcode/DerivedData", isSelected: true,
            matchesApp: { name, id in id == "com.apple.dt.xcode" || name == "xcode" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.ios_simulators", fallbackTitle: "iOS Simulators Data",
            category: .iosSimulators, relativeHomePath: "Library/Developer/CoreSimulator", isSelected: true,
            matchesApp: { name, id in id == "com.apple.dt.xcode" || name == "xcode" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.command_line_tools", fallbackTitle: "Xcode Command Line Tools",
            category: .xcode, absolutePath: "/Library/Developer/CommandLineTools", isSelected: true,
            matchesApp: { name, id in id == "com.apple.dt.xcode" || name == "xcode" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.xcode_archives", fallbackTitle: "Xcode Archives",
            category: .xcode, relativeHomePath: "Library/Developer/Xcode/Archives", isSelected: true,
            matchesApp: { name, id in id == "com.apple.dt.xcode" || name == "xcode" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.xcode_user_data", fallbackTitle: "Xcode User Data",
            category: .xcode, relativeHomePath: "Library/Developer/Xcode/UserData", isSelected: true,
            matchesApp: { name, id in id == "com.apple.dt.xcode" || name == "xcode" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.swiftpm_cache", fallbackTitle: "Swift Package Manager Cache",
            category: .swiftPMCache, relativeHomePath: "Library/Caches/org.swift.swiftpm", isSelected: true,
            matchesApp: { name, id in id == "com.apple.dt.xcode" || name == "xcode" }
        ),

        // Android Studio
        DeveloperPathEntry(
            titleKey: "developer.android_sdk", fallbackTitle: "Android SDK & NDK",
            category: .androidSDK, relativeHomePath: "Library/Android", isSelected: false,
            matchesApp: { name, id in name.contains("android studio") || id.contains("android.studio") }
        ),
        DeveloperPathEntry(
            titleKey: "developer.gradle_cache", fallbackTitle: "Gradle Caches & Wrappers",
            category: .gradleMaven, relativeHomePath: ".gradle", isSelected: true,
            matchesApp: { name, id in name.contains("android studio") || id.contains("android.studio") }
        ),
        DeveloperPathEntry(
            titleKey: "developer.android_data", fallbackTitle: "Android Data & AVDs",
            category: .androidCaches, relativeHomePath: ".android", isSelected: true,
            matchesApp: { name, id in name.contains("android studio") || id.contains("android.studio") }
        ),

        // Docker & OrbStack
        DeveloperPathEntry(
            titleKey: "developer.docker", fallbackTitle: "Docker Containers & Images",
            category: .docker, relativeHomePath: "Library/Containers/com.docker.docker", isSelected: false,
            matchesApp: { name, id in name.contains("docker") || id == "com.docker.docker" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.docker_user", fallbackTitle: "Docker Engine Data",
            category: .docker, relativeHomePath: ".docker", isSelected: false,
            matchesApp: { name, id in name.contains("docker") || id == "com.docker.docker" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.orbstack_data", fallbackTitle: "OrbStack Machines & Data",
            category: .docker, relativeHomePath: ".orbstack", isSelected: false,
            matchesApp: { name, id in name.contains("orbstack") || id == "dev.orbstack" }
        ),

        // JetBrains
        DeveloperPathEntry(
            titleKey: "developer.jetbrains_support", fallbackTitle: "JetBrains Application Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/JetBrains", isSelected: true,
            matchesApp: { name, _ in name.contains("jetbrains") || name.contains("idea") || name.contains("clion") || name.contains("webstorm") || name.contains("pycharm") || name.contains("rider") || name.contains("goland") }
        ),
        DeveloperPathEntry(
            titleKey: "developer.jetbrains_caches", fallbackTitle: "JetBrains IDE Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/JetBrains", isSelected: true,
            matchesApp: { name, _ in name.contains("jetbrains") || name.contains("idea") || name.contains("clion") || name.contains("webstorm") || name.contains("pycharm") || name.contains("rider") || name.contains("goland") }
        ),

        // VS Code
        DeveloperPathEntry(
            titleKey: "developer.vscode_extensions", fallbackTitle: "VS Code Extensions",
            category: .ideCaches, relativeHomePath: ".vscode/extensions", isSelected: false,
            matchesApp: { name, id in name == "visual studio code" || name == "code" || id == "com.microsoft.vscode" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.vscode_support", fallbackTitle: "VS Code Data",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Code", isSelected: true,
            matchesApp: { name, id in name == "visual studio code" || name == "code" || id == "com.microsoft.vscode" }
        ),

        // Cursor
        DeveloperPathEntry(
            titleKey: "developer.cursor_user", fallbackTitle: "Cursor IDE Settings & Extensions",
            category: .ideCaches, relativeHomePath: ".cursor", isSelected: false,
            matchesApp: { name, id in name == "cursor" || id.contains("cursor") || id == "com.todesktop.230313mzl4w4u92" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.cursor_support", fallbackTitle: "Cursor Application Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Cursor", isSelected: true,
            matchesApp: { name, id in name == "cursor" || id.contains("cursor") || id == "com.todesktop.230313mzl4w4u92" }
        ),

        // OpenCode
        DeveloperPathEntry(
            titleKey: "developer.opencode_cache", fallbackTitle: "OpenCode Cache",
            category: .ideCaches, relativeHomePath: ".cache/opencode", isSelected: true,
            matchesApp: { name, id in name.contains("opencode") || id.contains("opencode") }
        ),
        DeveloperPathEntry(
            titleKey: "developer.opencode_config", fallbackTitle: "OpenCode Config",
            category: .ideCaches, relativeHomePath: ".config/opencode", isSelected: false,
            matchesApp: { name, id in name.contains("opencode") || id.contains("opencode") }
        ),
        DeveloperPathEntry(
            titleKey: "developer.opencode_share", fallbackTitle: "OpenCode Data",
            category: .ideCaches, relativeHomePath: ".local/share/opencode", isSelected: true,
            matchesApp: { name, id in name.contains("opencode") || id.contains("opencode") }
        ),

        // Zed
        DeveloperPathEntry(
            titleKey: "developer.zed_support", fallbackTitle: "Zed Application Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Zed", isSelected: true,
            matchesApp: { name, id in name == "zed" || id == "dev.zed.zed" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.zed_caches", fallbackTitle: "Zed Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/dev.zed.Zed", isSelected: true,
            matchesApp: { name, id in name == "zed" || id == "dev.zed.zed" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.zed_config", fallbackTitle: "Zed Config",
            category: .ideCaches, relativeHomePath: ".config/zed", isSelected: false,
            matchesApp: { name, id in name == "zed" || id == "dev.zed.zed" }
        ),

        // Sublime Text
        DeveloperPathEntry(
            titleKey: "developer.sublime_support", fallbackTitle: "Sublime Text Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Sublime Text", isSelected: true,
            matchesApp: { name, id in name.contains("sublime text") || id == "com.sublimetext.4" || id == "com.sublimetext.3" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.sublime_support_3", fallbackTitle: "Sublime Text 3 Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Sublime Text 3", isSelected: true,
            matchesApp: { name, id in name.contains("sublime text") || id == "com.sublimetext.4" || id == "com.sublimetext.3" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.sublime_caches", fallbackTitle: "Sublime Text Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/com.sublimetext.4", isSelected: true,
            matchesApp: { name, id in name.contains("sublime text") || id == "com.sublimetext.4" || id == "com.sublimetext.3" }
        ),

        // Nova (Panic)
        DeveloperPathEntry(
            titleKey: "developer.nova_support", fallbackTitle: "Nova Extensions & Data",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Nova", isSelected: true,
            matchesApp: { name, id in name == "nova" || id == "com.panic.nova" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.nova_caches", fallbackTitle: "Nova Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/com.panic.Nova", isSelected: true,
            matchesApp: { name, id in name == "nova" || id == "com.panic.nova" }
        ),

        // Unity
        DeveloperPathEntry(
            titleKey: "developer.unity_support", fallbackTitle: "Unity Application Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Unity", isSelected: true,
            matchesApp: { name, id in name == "unity" || name == "unity hub" || id == "com.unity3d.unityhub" || id.hasPrefix("com.unity3d.unityeditor") }
        ),
        DeveloperPathEntry(
            titleKey: "developer.unity_hub_support", fallbackTitle: "Unity Hub Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/UnityHub", isSelected: true,
            matchesApp: { name, id in name == "unity" || name == "unity hub" || id == "com.unity3d.unityhub" || id.hasPrefix("com.unity3d.unityeditor") }
        ),
        DeveloperPathEntry(
            titleKey: "developer.unity_caches", fallbackTitle: "Unity Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/com.unity3d.UnityEditor", isSelected: true,
            matchesApp: { name, id in name == "unity" || name == "unity hub" || id == "com.unity3d.unityhub" || id.hasPrefix("com.unity3d.unityeditor") }
        ),

        // Eclipse
        DeveloperPathEntry(
            titleKey: "developer.eclipse_data", fallbackTitle: "Eclipse Data & Workspaces",
            category: .ideCaches, relativeHomePath: ".eclipse", isSelected: true,
            matchesApp: { name, id in name.contains("eclipse") || id == "org.eclipse.eclipse" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.eclipse_p2", fallbackTitle: "Eclipse P2 Agent",
            category: .ideCaches, relativeHomePath: ".p2", isSelected: true,
            matchesApp: { name, id in name.contains("eclipse") || id == "org.eclipse.eclipse" }
        ),

        // Visual Studio for Mac
        DeveloperPathEntry(
            titleKey: "developer.vsmac_support", fallbackTitle: "Visual Studio Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/VisualStudio", isSelected: true,
            matchesApp: { name, id in name == "visual studio" || id == "com.microsoft.visual-studio" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.vsmac_caches", fallbackTitle: "Visual Studio Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/VisualStudio", isSelected: true,
            matchesApp: { name, id in name == "visual studio" || id == "com.microsoft.visual-studio" }
        ),

        // Postman
        DeveloperPathEntry(
            titleKey: "developer.postman_support", fallbackTitle: "Postman Data & Workspaces",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Postman", isSelected: true,
            matchesApp: { name, id in name == "postman" || id == "com.postmanlabs.mac" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.postman_caches", fallbackTitle: "Postman Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/com.postmanlabs.mac", isSelected: true,
            matchesApp: { name, id in name == "postman" || id == "com.postmanlabs.mac" }
        ),

        // Insomnia
        DeveloperPathEntry(
            titleKey: "developer.insomnia_support", fallbackTitle: "Insomnia Application Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Insomnia", isSelected: true,
            matchesApp: { name, id in name == "insomnia" || id == "com.insomnia.app" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.insomnia_caches", fallbackTitle: "Insomnia Caches",
            category: .ideCaches, relativeHomePath: "Library/Caches/com.insomnia.app", isSelected: true,
            matchesApp: { name, id in name == "insomnia" || id == "com.insomnia.app" }
        ),

        // Atom (Legacy)
        DeveloperPathEntry(
            titleKey: "developer.atom_home", fallbackTitle: "Atom Settings & Packages",
            category: .ideCaches, relativeHomePath: ".atom", isSelected: false,
            matchesApp: { name, id in name == "atom" || id == "com.github.atom" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.atom_support", fallbackTitle: "Atom Application Support",
            category: .ideCaches, relativeHomePath: "Library/Application Support/Atom", isSelected: false,
            matchesApp: { name, id in name == "atom" || id == "com.github.atom" }
        ),

        // Neovim / Vim
        DeveloperPathEntry(
            titleKey: "developer.nvim_share", fallbackTitle: "Neovim Data & Plugins",
            category: .ideCaches, relativeHomePath: ".local/share/nvim", isSelected: false,
            matchesApp: { name, _ in name == "nvim" || name == "neovim" || name == "vim" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.nvim_state", fallbackTitle: "Neovim State",
            category: .ideCaches, relativeHomePath: ".local/state/nvim", isSelected: false,
            matchesApp: { name, _ in name == "nvim" || name == "neovim" || name == "vim" }
        ),
        DeveloperPathEntry(
            titleKey: "developer.nvim_cache", fallbackTitle: "Neovim Caches",
            category: .ideCaches, relativeHomePath: ".cache/nvim", isSelected: false,
            matchesApp: { name, _ in name == "nvim" || name == "neovim" || name == "vim" }
        ),
    ]

    public static func detect(
        appName: String,
        bundleID: String?,
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        fileSystemContext: FileSystemContext? = nil
    ) async -> [UninstallerService.RelatedCleanupComponent] {
        let fm = fileManager
        let home = (fileSystemContext?.homeDirectory ?? homeDirectory ?? fm.homeDirectoryForCurrentUser).path
        var components: [UninstallerService.RelatedCleanupComponent] = []
        let lowerName = appName.lowercased()
        let lowerID = bundleID?.lowercased() ?? ""

        for entry in pathMap {
            guard entry.matchesApp(lowerName, lowerID) else { continue }
            let path: String
            if let rel = entry.relativeHomePath {
                path = NormalizedPath.joinHome(home, rel)
            } else if let abs = entry.absolutePath {
                path = abs
            } else {
                continue
            }

            let url = NormalizedPath.url(path, isDirectory: true)
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = fm.getPhysicalDirectorySize(url: url, excludedPaths: [])
            guard size > 0 else { continue }

            let title = entry.titleKey.localized != entry.titleKey ? entry.titleKey.localized : entry.fallbackTitle
            components.append(UninstallerService.RelatedCleanupComponent(
                title: title,
                category: entry.category,
                sizeBytes: size,
                url: url,
                isSelected: entry.isSelected
            ))
        }

        return components.uniquedByPath()
    }
}

private extension Array where Element == UninstallerService.RelatedCleanupComponent {
    func uniquedByPath() -> [UninstallerService.RelatedCleanupComponent] {
        var seen = Set<String>()
        var result: [UninstallerService.RelatedCleanupComponent] = []
        for component in self {
            let pathKey = NormalizedPath.key(component.url)
            guard seen.insert(pathKey).inserted else { continue }
            result.append(component)
        }
        return result
    }
}
