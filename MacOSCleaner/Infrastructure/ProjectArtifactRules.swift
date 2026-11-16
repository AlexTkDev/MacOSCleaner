import Foundation

/// Single source of truth for project-local build artifact detection shared
/// by `CleanupEngine` and `SafetyManager`.
enum ProjectArtifactRules {
    static let rootDirectoryNames: [String] = [
        "Documents",
        "Desktop",
        "Developer",
        "Projects",
        "repos",
        "src",
        "workspace",
        "code",
    ]

    static let rootPrefixesLowercased: [String] = rootDirectoryNames.map { "/\($0.lowercased())/" }

    /// Unambiguous tool-specific artifact/cache directories requiring no sibling marker.
    static let alwaysRemovableNames: Set<String> = [
        "deriveddata",
        ".dart_tool",
        "__pycache__",
        ".pytest_cache",
        ".mypy_cache",
        ".ruff_cache",
        ".tox",
        ".next",
        ".nuxt",
        ".turbo",
        ".parcel-cache",
        ".angular",
        ".svelte-kit",
        ".zig-cache",
        ".bloop",
        ".metals",
    ]

    /// Universal or tool-shared directory names that require a sibling project marker.
    static let conditionalSiblingMarkers: [String: [String]] = [
        ".build": ["Package.swift", "project.yml"],
        "build": [
            ".xcodeproj", ".xcworkspace", "Package.swift", "project.yml",
            "build.gradle", "build.gradle.kts", "CMakeLists.txt", "Makefile",
            "pubspec.yaml", "pom.xml", "Cargo.toml", "pyproject.toml",
            "package.json", "tsconfig.json",
        ],
        ".gradle": ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        ".flutter-plugins": ["pubspec.yaml"],
        ".flutter-plugins-dependencies": ["pubspec.yaml"],
        "node_modules": ["package.json"],
        "dist": [
            "package.json", "tsconfig.json", "pyproject.toml", "setup.py",
            "vite.config.ts", "vite.config.js", "webpack.config.js", "rollup.config.js",
        ],
        "target": ["Cargo.toml", "pom.xml", "build.gradle", "build.gradle.kts"],
        "vendor": ["go.mod", "composer.json"],
        "venv": ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"],
        ".venv": ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"],
        ".eggs": ["setup.py", "pyproject.toml"],
        "cmakefiles": ["CMakeLists.txt", "CMakeCache.txt"],
        "coverage": [
            "package.json", "tsconfig.json", "pyproject.toml", "setup.py",
            "Cargo.toml", "go.mod", "Package.swift", "composer.json",
            "CMakeLists.txt", "build.gradle", "build.gradle.kts", "pom.xml",
        ],
        ".output": ["package.json", "tsconfig.json", "nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs"],
    ]

    static let gradleMarkers: [String] = [
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
    ]

    static let skipDescentNames: Set<String> = [".git", ".svn", ".hg", "Pods", ".cocoapods"]

    static func searchRoots(home: String) -> [String] {
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        return rootDirectoryNames.map { "\(base)/\($0)" }
    }

    static func isArtifact(at url: URL, home: String, fileManager: FileManager = .default) -> Bool {
        let standardized = url.standardizedFileURL
        let path = standardized.path
        let homeLower = (home.hasSuffix("/") ? String(home.dropLast()) : home).lowercased()
        let lower = path.lowercased()

        let roots = rootDirectoryNames.map { "\(homeLower)/\($0.lowercased())/" }
        guard let matchingRoot = roots.first(where: { lower.hasPrefix($0) }) else { return false }
        if lower.contains("/.vscode") || lower.contains("/.idea") || lower.contains("/.zed") { return false }

        // Direct children of ~/Documents or ~/Desktop are never treated as project artifacts.
        if matchingRoot == "\(homeLower)/documents/" || matchingRoot == "\(homeLower)/desktop/" {
            let relative = lower.dropFirst(matchingRoot.count)
            let segments = relative.split(separator: "/", omittingEmptySubsequences: true)
            guard segments.count >= 2 else { return false }
        }

        let nameLower = standardized.lastPathComponent.lowercased()
        if alwaysRemovableNames.contains(nameLower) {
            return true
        }

        if nameLower == "build-cache" {
            let parent = standardized.deletingLastPathComponent()
            guard parent.lastPathComponent.lowercased() == ".gradle" else { return false }
            let projectRoot = parent.deletingLastPathComponent()
            return hasAnySiblingMarker(gradleMarkers, in: projectRoot, fileManager: fileManager)
        }

        guard let requiredMarkers = conditionalSiblingMarkers[nameLower] else {
            return false
        }
        let parent = standardized.deletingLastPathComponent()
        return hasAnySiblingMarker(requiredMarkers, in: parent, fileManager: fileManager)
    }

    static func hasAnySiblingMarker(_ markers: [String], in directory: URL, fileManager: FileManager) -> Bool {
        guard let siblings = try? fileManager.contentsOfDirectory(atPath: directory.path), !siblings.isEmpty else {
            return false
        }
        for required in markers {
            if required.hasPrefix(".") && (required.contains("proj") || required.contains("workspace")) {
                if siblings.contains(where: { $0.hasSuffix(required) }) { return true }
            } else if siblings.contains(required) {
                return true
            }
        }
        return false
    }
}
