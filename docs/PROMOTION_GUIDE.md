# Global Search Visibility & Promotion Guide (SEO & GEO) for MacOSCleaner

Actionable guide for maximizing the discoverability and visibility of MacOSCleaner across international search engines (Google, Bing, DuckDuckGo), AI search platforms (ChatGPT Search, Perplexity, Apple Intelligence, Google AI Overviews), global macOS directories, and worldwide developer communities.

---

## 1. Global Search Engines & Webmaster Consoles

### Google Search Console (Primary Global Target)
Google accounts for ~90%+ of international desktop search traffic.
1. **Ownership Verification**: Validated via `google5148679afd9a2794.html`.
2. **Sitemap Submission**: In Google Search Console, submit:
   `https://alextkdev.github.io/MacOSCleaner/sitemap.xml`
3. **Rich Results Validation**:
   - Verify URLs with the [Google Rich Results Test](https://search.google.com/test/rich-results).
   - Core Schema.org entities configured:
     - `SoftwareApplication`: Global category `UtilitiesApplication`, version `2.1.1`, direct DMG download URL, $0 free `Offer`, feature list, and author ORCID.
     - `WebSite`: Alternative names, description, English canonical tags, publisher info.
     - `FAQPage`: Rich FAQ accordions displayed directly in search result snippets.
     - `BreadcrumbList`: Site navigation hierarchy.

### Bing Webmaster Tools & IndexNow (Bing, DuckDuckGo, Yahoo, Copilot)
1. **Multi-Engine Reach**: Bing indexes queries for Bing, DuckDuckGo, Yahoo, Ecosia, and Microsoft Copilot.
   - Import site directly from Google Search Console via [Bing Webmaster Tools](https://www.bing.com/webmasters).
   - Submit `https://alextkdev.github.io/MacOSCleaner/sitemap.xml`.
2. **IndexNow (Instant Global Crawling)**:
   - Notifies participating global search engines immediately when new releases or landing page updates are pushed to `gh-pages`.

---

## 2. Generative Engine Optimization (GEO — AI Search Visibility)

Global tech users and Mac power users increasingly rely on Perplexity, ChatGPT Search, Claude, and Apple Intelligence for software recommendations.

### `llms.txt` Standard
- **`https://alextkdev.github.io/MacOSCleaner/llms.txt`**: Standardized Markdown brief for LLM agents (product specs, macOS 26+ / Apple Silicon architecture, dual licensing, key links).
- **`https://alextkdev.github.io/MacOSCleaner/llms-full.txt`**: Complete architectural context, 1,770 cleanup path rules across 251 apps and 66 CLI toolchains, cryptographic duplicate file finder pipeline, and privacy model.

### `robots.txt` AI Crawler Directives
Explicit permissions configured in `docs/robots.txt` for all major global AI search crawlers:
- `GPTBot`, `ChatGPT-User`, `OAI-SearchBot` (OpenAI / ChatGPT Search)
- `ClaudeBot`, `Claude-Web`, `anthropic-ai` (Anthropic)
- `PerplexityBot`, `Perplexity-User` (Perplexity AI)
- `Applebot-Extended` (Apple Intelligence, Spotlight & Siri web queries)
- `Google-Extended`, `GoogleOther` (Google Gemini & AI Overviews)

---

## 3. GitHub SEO & Global Discoverability

GitHub has immense domain authority (DA ~96) and ranks at the top of Google for developer and utility queries.

1. **Repository Topics**:
   Ensure the following global topics are set on the GitHub repository:
   `macos`, `cleaner`, `uninstaller`, `swiftui`, `swift6`, `apple-silicon`, `disk-cleanup`, `cache-cleaner`, `xcode-cleanup`, `docker-cleanup`, `duplicate-finder`, `appintents`, `privacy-first`, `offline-first`.

2. **About Section & Header**:
   - **Description**: `Free open-source macOS cleaner & app uninstaller for Apple Silicon. Clean caches, leftover app files, Xcode, Docker, Homebrew & duplicates. 100% offline, zero telemetry.`
   - **Website**: `https://alextkdev.github.io/MacOSCleaner/`

3. **Releases & Binary Distribution**:
   - Always attach notarized/signed `.dmg` and `.zip` binaries to every GitHub release.
   - Include searchable keywords in release titles and notes (e.g., `v2.1.1 — Touch ID sudo helper, privileged uninstaller & Spotlight rebuild`).

---

## 4. Global Distribution Channels & Software Directories

### Homebrew Cask (The #1 Mac Power-User & Developer Channel)
Homebrew is the standard package manager for millions of macOS developers worldwide.

1. **Official Homebrew Tap**:
   Create a repository `AlexTkDev/homebrew-tap` with `Casks/macoscleaner.rb`:
   ```ruby
   cask "macoscleaner" do
     version "2.1.1"
     sha256 "<SHA256_OF_DMG>"

     url "https://github.com/AlexTkDev/MacOSCleaner/releases/download/#{version}/MacOSCleaner.dmg",
         verified: "github.com/AlexTkDev/MacOSCleaner/"
     name "MacOSCleaner"
     desc "Free open-source cleaner and app uninstaller for Apple Silicon"
     homepage "https://alextkdev.github.io/MacOSCleaner/"

     depends_on arch: :arm64
     depends_on macos: ">= :sonoma"

     app "MacOSCleaner.app"

     zap trash: [
       "~/Library/Caches/input.MacOSCleaner",
       "~/Library/Preferences/input.MacOSCleaner.plist",
     ]
   end
   ```
   Users install in one command:
   ```bash
   brew install AlexTkDev/tap/macoscleaner
   ```

2. **Submit to `homebrew/cask` Core**:
   Submit a PR to the official `homebrew/cask` repository once the project establishes consistent release cadence and community stars.

### Global Software Directories & Alternatives
1. **AlternativeTo.net**:
   - Create a listing positioning MacOSCleaner as a free, privacy-first alternative to `CleanMyMac X`, `DaisyDisk`, `AppCleaner`, `OnyX`, and `GrandPerspective`.
   - Captures high-volume global search queries like *"free cleanmymac alternative macos"*.
2. **Open-Source Mac Apps**:
   - Submit via PR to [serhii-londar/open-source-mac-os-apps](https://github.com/serhii-londar/open-source-mac-os-apps) under *Utilities* and *Developer Tools*.
3. **Curated Awesome Lists**:
   - PR to [jaywcjlove/awesome-mac](https://github.com/jaywcjlove/awesome-mac) and [iCHAIT/awesome-macOS](https://github.com/iCHAIT/awesome-macOS).
4. **MacUpdate & Softpedia**:
   - Submit free listing applications to MacUpdate and Softpedia Mac.

---

## 5. Global Community Launches & Media

1. **Hacker News (Y Combinator)**:
   - Format: `Show HN: MacOSCleaner – Free, offline macOS cleaner written in Swift 6`
   - Key angles: Swift 6 structured concurrency, Apple Silicon optimization, zero telemetry, full offline transparency vs commercial subscription cleaners.
2. **Reddit**:
   - `r/mac` & `r/macapps`: Focus on utility benefits (no subscriptions, disk ring visuals, duplicate finder, deep uninstaller).
   - `r/apple`: Saturday promotion / self-promotion threads.
   - `r/swift`: Technical discussion of Liquid Glass, AppIntents / Siri voice integration, actor pipelines.
3. **Product Hunt**:
   - Prepare a launch with video demo, hero screenshots, and maker comment.
4. **Mac Newsletters & Apple Tech Press**:
   - Tip submission to MacStories, 9to5Mac, AppleInsider, and iOS Dev Weekly.
