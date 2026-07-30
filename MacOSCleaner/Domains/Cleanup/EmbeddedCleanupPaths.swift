import Foundation

public enum EmbeddedCleanupPaths {

    // MARK: - App Caches

    public static let appCaches: [CleanupPath] = [
        // Never ~/Library/Caches/Google wholesale — updater/Keystone live under Google trees.
        CleanupPath(path: "~/Library/Caches/Google/Chrome", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/org.carthage.CarthageKit", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/CocoaPods", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/pip", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/Homebrew", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/ms-playwright-go", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.spotify.client", category: .appCaches),
        CleanupPath(path: "~/Library/Application Support/Spotify/PersistentCache", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/us.zoom.xos", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.dt.Xcode", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.dt.instruments", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/org.swift.swiftpm", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.plausiblelabs.crashreporter.data", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/JetBrains", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.dt.SourceKitService", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.dt.XcodePreviews", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/pnpm", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/yarn", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/npm", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/go-build", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/Adobe", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.discordapp.Discord", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.microsoft.teams2", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.slack.Slack", category: .appCaches),
        CleanupPath(path: "~/Library/Caches/com.tinyspeck.slackmacgap", category: .appCaches),
        CleanupPath(path: "/Library/Caches", category: .appCaches, requiresSudo: true),
    ]

    // MARK: - Browser Caches

    public static let browserCaches: [CleanupPath] = [
        CleanupPath(path: "~/Library/Caches/com.apple.Safari", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/Apple/com.apple.Safari", category: .browserCaches),
        CleanupPath(path: "~/Library/WebKit/WebsiteData", category: .browserCaches),
        CleanupPath(path: "~/Library/Safari/Favicon Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Safari/Touch Icons Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Safari/Template Icons", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/com.brave.Browser", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/com.operasoftware.Opera", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/com.microsoft.Edge", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/org.mozilla.firefox", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/Firefox", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/com.google.Chrome", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/com.google.Chrome.beta", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.WebKit.Networking", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/BraveSoftware", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/com.vivaldi.Vivaldi", category: .browserCaches),
        CleanupPath(path: "~/Library/Caches/company.thebrowser.Browser", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Google/Chrome/Default/Code Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Google/Chrome/Default/GPUCache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Google/Chrome/Default/Service Worker/ScriptCache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Google/Chrome/GrShaderCache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Firefox/Profiles/*/cache2", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Firefox/Profiles/*/startupCache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Firefox/Profiles/*/thumbnails", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Microsoft Edge/Default/Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Microsoft Edge/Default/Code Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Code Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Arc/User Data/Default/Cache", category: .browserCaches),
        CleanupPath(path: "~/Library/Application Support/Arc/User Data/Default/Code Cache", category: .browserCaches),
    ]

    // MARK: - Messaging / Media

    public static let messagingMedia: [CleanupPath] = [
        CleanupPath(path: "~/Library/Caches/ru.keepcoder.Telegram", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/com.tinyspeck.slackmacgap", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/com.hnc.Discord", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/com.spotify.client", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/us.zoom.xos", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/com.signal.Signal", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/com.tencent.xinWeChat", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/com.microsoft.teams2", category: .messagingMedia),
        CleanupPath(path: "~/Library/Caches/net.whatsapp.WhatsApp", category: .messagingMedia),
    ]

    // MARK: - IDE Caches

    public static let ideCaches: [CleanupPath] = [
        // Cursor
        CleanupPath(path: "~/Library/Application Support/Cursor/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/CachedExtensionVSIXs", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/User/workspaceStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/Crashpad", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/Service Worker/CacheStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Cursor/Service Worker/ScriptCache", category: .ideCaches),
        // VS Code
        CleanupPath(path: "~/Library/Application Support/Code/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/CachedExtensionVSIXs", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/User/workspaceStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/Crashpad", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/Service Worker/CacheStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Code/Service Worker/ScriptCache", category: .ideCaches),
        // Windsurf
        CleanupPath(path: "~/Library/Application Support/Windsurf/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/CachedExtensionVSIXs", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/User/workspaceStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/Crashpad", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/Service Worker/CacheStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Windsurf/Service Worker/ScriptCache", category: .ideCaches),
        // Zed
        CleanupPath(path: "~/Library/Application Support/dev.zed.Zed/cache", category: .ideCaches),
        CleanupPath(path: "~/.config/zed/cache", category: .ideCaches),
        // opencode Desktop
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/CachedExtensionVSIXs", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/User/workspaceStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/Crashpad", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/Service Worker/CacheStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ai.opencode.desktop/Service Worker/ScriptCache", category: .ideCaches),
        // Nova
        CleanupPath(path: "~/Library/Application Support/Nova/Caches", category: .ideCaches),
        CleanupPath(path: "~/Library/Caches/com.panic.Nova", category: .ideCaches),
        // Sublime Text
        CleanupPath(path: "~/Library/Application Support/Sublime Text/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Sublime Text/Index", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Sublime Text/Package Control.cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Caches/com.sublimetext.4", category: .ideCaches),
        // JetBrains
        CleanupPath(path: "~/Library/Caches/JetBrains", category: .ideCaches),
        CleanupPath(path: "~/Library/Logs/JetBrains", category: .ideCaches),
        // GitHub Desktop
        CleanupPath(path: "~/Library/Application Support/GitHub Desktop/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/GitHub Desktop/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/GitHub Desktop/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/GitHub Desktop/GPUCache", category: .ideCaches),
        // Figma / Notion / Linear / Postman / Insomnia
        CleanupPath(path: "~/Library/Application Support/Figma/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Figma/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Figma/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Figma/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Notion/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Notion/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Notion/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Notion/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Linear/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Linear/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Linear/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Linear/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Postman/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Postman/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Postman/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Postman/GPUCache", category: .ideCaches),
        // Claude / ChatGPT
        CleanupPath(path: "~/Library/Application Support/Claude/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Claude/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Claude/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Claude/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Claude/Service Worker/CacheStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Claude/Service Worker/ScriptCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Claude/Crashpad", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ChatGPT/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ChatGPT/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ChatGPT/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ChatGPT/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ChatGPT/Service Worker/CacheStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ChatGPT/Service Worker/ScriptCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/ChatGPT/Crashpad", category: .ideCaches),
        // Slack / Discord
        CleanupPath(path: "~/Library/Application Support/Slack/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Slack/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Slack/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Slack/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Slack/Service Worker/CacheStorage", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/Slack/Service Worker/ScriptCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/discord/Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/discord/CachedData", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/discord/Code Cache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/discord/GPUCache", category: .ideCaches),
        CleanupPath(path: "~/Library/Application Support/discord/Crashpad", category: .ideCaches),
        // GitHub Desktop
        CleanupPath(path: "~/Library/Caches/com.github.GitHubClient", category: .ideCaches),
        CleanupPath(path: "~/Library/Caches/com.github.GitHubClient.ShipIt", category: .ideCaches),
        // DBeaver
        CleanupPath(path: "~/Library/Caches/org.jkiss.dbeaver.core.product", category: .ideCaches),
        // TablePlus
        CleanupPath(path: "~/Library/Caches/com.tinyapp.TablePlus", category: .ideCaches),
        CleanupPath(path: "~/Library/Caches/com.tableplus.TablePlus", category: .ideCaches),
        // Vivaldi
        CleanupPath(path: "~/Library/Caches/com.vivaldi.Vivaldi", category: .ideCaches),
    ]

    // MARK: - Language Caches

    public static let languageCaches: [CleanupPath] = [
        CleanupPath(path: "~/.cargo/registry/cache", category: .languageCaches),
        CleanupPath(path: "~/.cargo/registry/src", category: .languageCaches),
        CleanupPath(path: "~/.cargo/.package-cache", category: .languageCaches),
        CleanupPath(path: "~/.cargo/git", category: .languageCaches),
        CleanupPath(path: "~/.bun/install/cache", category: .languageCaches),
        CleanupPath(path: "~/.deno/cache", category: .languageCaches),
        CleanupPath(path: "~/Library/Caches/deno", category: .languageCaches),
        CleanupPath(path: "~/.volta/cache", category: .languageCaches),
        CleanupPath(path: "~/.nvm/.cache", category: .languageCaches),
        CleanupPath(path: "~/.cache/node-gyp", category: .languageCaches),
        CleanupPath(path: "~/.node-gyp", category: .languageCaches),
        CleanupPath(path: "~/.cache/Cypress", category: .languageCaches),
        CleanupPath(path: "~/Library/Caches/Cypress", category: .languageCaches),
        CleanupPath(path: "~/.cache/ms-playwright", category: .languageCaches),
        CleanupPath(path: "~/.cache/ms-playwright-go", category: .languageCaches),
        CleanupPath(path: "~/Library/Caches/ms-playwright", category: .languageCaches),
        CleanupPath(path: "~/.cache/puppeteer", category: .languageCaches),
        CleanupPath(path: "~/.composer/cache", category: .languageCaches),
        CleanupPath(path: "~/Library/Caches/pypoetry", category: .languageCaches),
        CleanupPath(path: "~/Library/Caches/uv", category: .languageCaches),
        CleanupPath(path: "~/.cache/pip", category: .languageCaches),
        CleanupPath(path: "~/.cache/pypoetry", category: .languageCaches),
        CleanupPath(path: "~/.cache/uv", category: .languageCaches),
        CleanupPath(path: "~/.cache/hatch", category: .languageCaches),
        CleanupPath(path: "~/.rye/cache", category: .languageCaches),
        CleanupPath(path: "~/.cache/pipx", category: .languageCaches),
        CleanupPath(path: "~/.sbt", category: .languageCaches),
        CleanupPath(path: "~/.ivy2/cache", category: .languageCaches),
        CleanupPath(path: "~/.coursier/cache", category: .languageCaches),
        CleanupPath(path: "~/.ammonite/cache", category: .languageCaches),
        CleanupPath(path: "~/.cache/metals", category: .languageCaches),
        CleanupPath(path: "~/.julia/compiled", category: .languageCaches),
        CleanupPath(path: "~/.julia/logs", category: .languageCaches),
        CleanupPath(path: "~/.hex/packages", category: .languageCaches),
        CleanupPath(path: "~/.cabal/packages", category: .languageCaches),
        CleanupPath(path: "~/.cabal/logs", category: .languageCaches),
        CleanupPath(path: "~/.cache/org.swift.swiftpm", category: .languageCaches),
        CleanupPath(path: "~/.swiftpm/cache", category: .languageCaches),
        CleanupPath(path: "~/.swiftpm/repositories", category: .languageCaches),
        CleanupPath(path: "~/.pnpm-store", category: .languageCaches),
        CleanupPath(path: "~/.yarn", category: .languageCaches),
        CleanupPath(path: "~/.cache/yarn", category: .languageCaches),
        CleanupPath(path: "~/.cache/poetry", category: .languageCaches),
        CleanupPath(path: "~/.cache/bazel", category: .languageCaches),
        CleanupPath(path: "~/.cache/bazelisk", category: .languageCaches),
        CleanupPath(path: "~/.gem", category: .languageCaches),
        CleanupPath(path: "~/.cocoapods", category: .languageCaches),
        CleanupPath(path: "~/.pub-cache/hosted", category: .languageCaches),
        CleanupPath(path: "~/.pub-cache/git", category: .languageCaches),
        CleanupPath(path: "~/.dartServer", category: .languageCaches),
    ]

    // MARK: - System Caches

    public static let systemCaches: [CleanupPath] = [
        CleanupPath(path: "~/Library/Caches/com.apple.QuickLook.thumbnailcache", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.fontd", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.iconservices", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.metadata.SpotlightIndex", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.Siri", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.Assistant", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.parsecd", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.helpd", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/CloudKit", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.TimeMachine", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.diagnosticd", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.Spotlight", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.quicklook.ThumbnailsAgent", category: .systemCaches),
        CleanupPath(path: "~/Library/Caches/com.apple.quicklook.ThumbnailsAgent/Thumbnails", category: .systemCaches),
    ]

    // MARK: - Dotfile Caches

    public static let dotfileCaches: [CleanupPath] = [
        CleanupPath(path: "~/.config/opencode/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.config/claude-cli/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.config/gemini/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.config/aider/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.config/continue/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.config/cody/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.npm/_logs", category: .dotfileCaches),
        CleanupPath(path: "~/.terraform.d/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.cache/helm/repository", category: .dotfileCaches),
        CleanupPath(path: "~/.cache/bazel", category: .dotfileCaches),
        CleanupPath(path: "~/.ccache", category: .dotfileCaches),
        CleanupPath(path: "~/.vcpkg/cache", category: .dotfileCaches),
        CleanupPath(path: "~/.local/share/Trash", category: .dotfileCaches),
    ]

    // MARK: - User Logs

    public static let userLogs: [CleanupPath] = [
        CleanupPath(path: "~/Library/Logs", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/DiagnosticReports", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/CrashReporter", category: .userLogs),
        CleanupPath(path: "~/Library/Application Support/CrashReporter", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/PanicReporter", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Retired", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/MobileSlideshows", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/stackshot", category: .userLogs),
        CleanupPath(path: "/Library/Logs", category: .userLogs, requiresSudo: true),
        CleanupPath(path: "/var/log", category: .userLogs, requiresSudo: true),
        CleanupPath(path: "~/Library/Logs/Adobe", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Microsoft", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Docker Desktop", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/JetBrains", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Homebrew", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/CoreSimulator", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Unity", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Unity Hub", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/EpicGamesLauncher", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Steam", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Zoom", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Postman", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/TablePlus", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/GitKraken", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Insomnia", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Figma", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/BraveSoftware", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Google/Chrome", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Firefox", category: .userLogs),
        CleanupPath(path: "~/Library/Logs/Microsoft Edge", category: .userLogs),
    ]

    // MARK: - Saved App State

    public static let savedAppState: [CleanupPath] = [
        CleanupPath(path: "~/Library/Saved Application State", category: .savedAppState),
    ]

    // MARK: - Crash Reporter

    public static let crashReporter: [CleanupPath] = [
        CleanupPath(path: "~/Library/Application Support/CrashReporter", category: .crashReporter),
        CleanupPath(path: "~/Library/Logs/DiagnosticReports", category: .crashReporter),
        CleanupPath(path: "/Library/Logs/DiagnosticReports", category: .crashReporter, requiresSudo: true),
    ]

    // MARK: - Mail Downloads

    public static let mailDownloads: [CleanupPath] = [
        CleanupPath(path: "~/Library/Mail Downloads", category: .mailDownloads),
        CleanupPath(path: "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", category: .mailDownloads),
        CleanupPath(path: "~/Library/Mail/*/Attachments", category: .mailDownloads),
    ]

    // MARK: - Launch Agents (NEW)

    public static let launchAgents: [CleanupPath] = [
        CleanupPath(path: "~/Library/LaunchAgents", category: .launchAgents),
    ]

    // MARK: - Launch Daemons (NEW)

    public static let launchDaemons: [CleanupPath] = [
        CleanupPath(path: "/Library/LaunchDaemons", category: .launchDaemons, requiresSudo: true),
    ]

    // MARK: - Privileged Helper Tools (NEW)

    public static let privilegedHelpers: [CleanupPath] = [
        CleanupPath(path: "/Library/PrivilegedHelperTools", category: .privilegedHelpers, requiresSudo: true),
    ]

    // MARK: - Package Receipts (NEW)

    public static let pkgReceipts: [CleanupPath] = [
        CleanupPath(path: "/Library/Receipts", category: .pkgReceipts, requiresSudo: true),
        CleanupPath(path: "~/Library/Receipts", category: .pkgReceipts),
    ]

    // MARK: - Internet Plugins (NEW)

    public static let internetPlugins: [CleanupPath] = [
        CleanupPath(path: "~/Library/Internet Plug-Ins", category: .internetPlugins),
        CleanupPath(path: "/Library/Internet Plug-Ins", category: .internetPlugins, requiresSudo: true),
    ]

    // MARK: - Shared File Lists (NEW)

    public static let sharedFileLists: [CleanupPath] = [
        CleanupPath(path: "~/Library/Application Support/com.apple.sharedfilelist", category: .sharedFileLists),
    ]

    // MARK: - Cloud Docs (NEW)

    public static let cloudDocs: [CleanupPath] = [
        CleanupPath(path: "~/Library/Application Support/CloudDocs", category: .cloudDocs),
    ]

    // MARK: - Photos Cache (NEW)

    public static let photosCache: [CleanupPath] = [
        CleanupPath(path: "~/Library/Containers/com.apple.Photos/Data/Library/Caches", category: .photosCache),
    ]

    // MARK: - Voice Memos (NEW)

    public static let voiceMemos: [CleanupPath] = [
        CleanupPath(path: "~/Library/Application Support/com.apple.VoiceMemos/Recordings", category: .voiceMemos),
    ]

    // MARK: - GarageBand / Logic Pro (NEW)

    public static let garageBandLogic: [CleanupPath] = [
        CleanupPath(path: "~/Music/GarageBand", category: .garageBandLogic),
        CleanupPath(path: "~/Music/Logic", category: .garageBandLogic),
        CleanupPath(path: "~/Library/Containers/com.apple.garageband10/Data/Library/Caches", category: .garageBandLogic),
    ]

    // MARK: - iMovie / Final Cut (NEW)

    public static let iMovieFinalCut: [CleanupPath] = [
        CleanupPath(path: "~/Movies/iMovie Library.imovielibrary", category: .iMovieFinalCut),
        CleanupPath(path: "~/Movies/Final Cut Pro Libraries", category: .iMovieFinalCut),
        CleanupPath(path: "~/Library/Caches/com.apple.iMovieApp", category: .iMovieFinalCut),
    ]

    // MARK: - Garmin / Fitbit (NEW)

    public static let garminFitbit: [CleanupPath] = [
        CleanupPath(path: "~/Library/Caches/com.garmin.connectiq", category: .garminFitbit),
        CleanupPath(path: "~/Library/Caches/com.fitbit.Fitbit-OS-Simulator", category: .garminFitbit),
    ]

    // MARK: - Old Backups (NEW)

    /// Discovery hints only — `cleanOldBackups` never wholesale-deletes these.
    /// `~/Backups` is intentionally absent (never clean that root).
    public static let oldBackups: [CleanupPath] = [
        CleanupPath(path: "~/Desktop/*.backup", category: .oldBackups),
        CleanupPath(path: "~/Documents/*.backup", category: .oldBackups),
        CleanupPath(path: "~/Downloads/*.backup", category: .oldBackups),
    ]

    // MARK: - Commands

    public static let dnsFlushCommands: [CleanupCommand] = [
        CleanupCommand(command: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder", description: "Flush DNS cache", requiresSudo: true, safe: true),
    ]

    public static let fontCacheCommands: [CleanupCommand] = [
        CleanupCommand(command: "sudo atsutil databases -remove", description: "Remove font databases", requiresSudo: true, safe: true, requiresRestart: true),
    ]

    public static let sleepImageCommands: [CleanupCommand] = [
        CleanupCommand(command: "sudo pmset hibernatemode 0; sudo rm /var/vm/sleepimage", description: "Disable hibernation and remove sleepimage", requiresSudo: true, safe: false),
    ]

    // MARK: - Accessor

    public static func paths(for category: CleanupCategory) -> [CleanupPath] {
        let base: [CleanupPath]
        switch category {
        case .appCaches: base = appCaches
        case .browserCaches: base = browserCaches
        case .messagingMedia: base = messagingMedia
        case .ideCaches: base = ideCaches
        case .languageCaches: base = languageCaches
        case .systemCaches: base = systemCaches
        case .dotfileCaches: base = dotfileCaches
        case .userLogs: base = userLogs
        case .savedAppState: base = savedAppState
        case .crashReporter: base = crashReporter
        case .mailDownloads: base = mailDownloads
        case .launchAgents: base = launchAgents
        case .launchDaemons: base = launchDaemons
        case .privilegedHelpers: base = privilegedHelpers
        case .pkgReceipts: base = pkgReceipts
        case .internetPlugins: base = internetPlugins
        case .sharedFileLists: base = sharedFileLists
        case .cloudDocs: base = cloudDocs
        case .photosCache: base = photosCache
        case .voiceMemos: base = voiceMemos
        case .garageBandLogic: base = garageBandLogic
        case .iMovieFinalCut: base = iMovieFinalCut
        case .garminFitbit: base = garminFitbit
        case .oldBackups: base = oldBackups
        default: base = []
        }
        let generated = GeneratedCleanupPaths.cachePaths(for: category)
        guard !generated.isEmpty else { return base }
        var seen = Set(base.map(\.path))
        var merged = base
        for path in generated where !seen.contains(path.path) {
            seen.insert(path.path)
            merged.append(path)
        }
        return merged
    }

    public static func commands(for category: CleanupCategory) -> [CleanupCommand] {
        switch category {
        case .dnsFlush: return dnsFlushCommands
        case .fontCache: return fontCacheCommands
        case .sleepImage: return sleepImageCommands
        default: return []
        }
    }
}
