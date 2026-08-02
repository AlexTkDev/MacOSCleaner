#!/usr/bin/env python3
"""One-shot migration of engine_paths.json / ui_metadata.json to schema v3.

Fixes documented in implementation_plan.md, phase 0:
  * merges "_1" duplicate keys and multi-id keys into `bundle_ids`
  * moves non-app entries (CLI toolchains, system caches) into `toolchains`
  * repairs or drops truncated paths, placeholders and documentation artifacts
  * classifies every path with `purpose` + `system` flags
  * collapses paths nested in a sibling of the same purpose
  * fills `parent_suite` in ui_metadata

Run from the repository root:  python3 scripts/migrate_engine_paths_v3.py
"""

from __future__ import annotations

import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "MacOSCleaner" / "Resources"
ENGINE = RESOURCES / "engine_paths.json"
UI = RESOURCES / "ui_metadata.json"

TOKENS = {
    "APP_SUPPORT", "CACHES", "PREFS", "CONTAINERS", "GROUP_CONTAINERS", "LOGS", "HOME",
    "SAVED_STATE", "USER_LIB", "USER_CONFIG", "USER_CACHE", "USER_LOCAL_SHARE", "VAR_FOLDERS",
    "SYS_LIB", "SYS_APP_SUPPORT", "SYS_LAUNCH_AGENTS", "SYS_LAUNCH_DAEMONS",
    "SYS_PRIV_HELPERS", "SYS_CACHES", "SYS_PREFS", "SYS_LOGS",
}
SYSTEM_TOKENS = {t for t in TOKENS if t.startswith("SYS_")}

# Absolute (non-token) prefixes allowed to stay in the base.
ABSOLUTE_ALLOWED = ("/usr/local/", "/opt/homebrew/", "/Library/", "/var/log/", "/var/root/")

# ---------------------------------------------------------------------------
# 1. Truncated paths, placeholders and documentation artifacts.
#    key -> {broken path: [replacements]}   ([] drops the path)
# ---------------------------------------------------------------------------

PATH_FIXES: dict[str, dict[str, list[str]]] = {
    # Covered by the dedicated Edge channels entry.
    "com.microsoft.edgemac": {"/Canary": []},
    "company.thebrowser.Browser": {"/Default/Cache": ["<APP_SUPPORT>/Arc/User Data/Default/Cache"]},
    "company.thebrowser.Browser_1": {
        "/Arc/Default/Extensions/": ["<APP_SUPPORT>/Arc/User Data/Default/Extensions"]
    },
    # Legacy Xcode 3 layout on a SIP-protected volume + a size annotation from the docs.
    "com.apple.dt.Xcode": {
        "/Developer/Library/uninstall-devtools": [],
        "/Developer/Applications/Xcode.app": [],
        "~2-5GB": [],
    },
    "com.apple.dt.Xcode_1": {"/Developer/Library/uninstall-devtools": [], "~2-5GB": []},
    "com.valvesoftware.steam": {
        "/compatdata/": ["<APP_SUPPORT>/Steam/steamapps/compatdata"],
        "/shadercache/": ["<APP_SUPPORT>/Steam/steamapps/shadercache"],
    },
    "com.tinyspeck.slackmacgap": {"/Slack/storage": ["<APP_SUPPORT>/Slack/storage"]},
    "com.microsoft.teams2": {"/Microsoft/Teams": ["<APP_SUPPORT>/Microsoft/Teams"]},
    "org.telegram.desktop": {
        "/user_data/stickers/": ["<APP_SUPPORT>/Telegram Desktop/tdata/user_data/stickers"],
        "/user_data/media_cache/": ["<APP_SUPPORT>/Telegram Desktop/tdata/user_data/media_cache"],
    },
    "com.spotify.client": {"/Storage": ["<CACHES>/com.spotify.client/Storage"]},
    "com.google.drivefs": {"/content_cache": [], "/metadata": []},  # covered by the glob entries
    "net.battle.bootstrapper": {"/Blizzard": ["<APP_SUPPORT>/Blizzard"], "/Applications/World": []},
    "com.mojang.minecraftlauncher": {
        "/saves/": ["<APP_SUPPORT>/minecraft/saves"],
        "/mods/": ["<APP_SUPPORT>/minecraft/mods"],
        "/versions/": ["<APP_SUPPORT>/minecraft/versions"],
        "/libraries/": ["<APP_SUPPORT>/minecraft/libraries"],
    },
    "com.panic.Transmit": {
        "/Favorites": ["<APP_SUPPORT>/Transmit/Favorites"],
        "/History": ["<APP_SUPPORT>/Transmit/History"],
    },
    "com.resilio.Sync": {"/.sync": ["<HOME>/.sync"]},
    "com.evernote.Evernote": {"/Evernote/": []},  # <CONTAINERS>/com.evernote.Evernote already listed
    # Ambiguous document-relative fragments — no safe reconstruction.
    "us.zoom.xos": {"/video": []},
    "com.apple.FinalCut": {"/proxy": []},
    "com.apple.logic10": {"/Logic/Plug-in": [], "/Audio/": []},
    "com.apple.Music / com.apple.iTunes": {
        "/Music": [], "/Tunes": [], "/Album": [], "/Backup/": [], "/iTunes": []
    },
    "com.parallels.desktop": {"/Backups/": []},
    "com.vmware.fusion": {"/VMware": []},
    "md.obsidian": {"/plugins/": [], "/themes/": []},  # vault-relative, not a fixed location
    # Toolchains: root-relative project artifacts belong to cleanProjectLocalBuildArtifacts.
    "com.vagrant.vagrant": {"/.vagrant/": []},
    "development.flutter": {"/build/": []},
    "development.terraform": {"/.terraform/": [], "/terraform.tfstate": []},
    "development.node_js_npm_nvm_fnm_pnpm_yarn_bun": {"/node_modules": []},
    "development.python_system_pyenv_conda_pip_poetry_pipenv": {
        "/__pycache__": [],
        "<HOME>/anaconda3 или ~/miniconda3": ["<HOME>/anaconda3", "<HOME>/miniconda3"],
    },
    "development.rust_rustup_cargo": {"/target/": []},
    "ai_tools.weights_biases_wandb": {"/wandb/": []},
    "ai_agents_and_coding.aider_ai_pair_programmer": {
        "/.aider.chat.history.md": ["<HOME>/.aider.chat.history.md"],
        "/.aider.tags.cache.v3": ["<HOME>/.aider.tags.cache.v3"],
    },
    "database_servers.mysql_mariadb_homebrew": {
        "/ibdata1": ["/usr/local/var/mysql/ibdata1", "/opt/homebrew/var/mysql/ibdata1"],
        "/mysql-bin.*": [],  # already covered by var/mysql/mysql-bin.* globs
        "/*.err": ["/usr/local/var/mysql/*.err", "/opt/homebrew/var/mysql/*.err"],
    },
    # SIP-protected system assets: never removable by the app.
    "com.apple.GenerativeModels": {
        "/System/Library/AssetsV2/": [],
        "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels": [],
    },
    # Vendor uninstall helper inside the bundle, not a residual.
    "com.docker.docker": {"/Applications/Docker.app/Contents/MacOS/uninstall": []},
    "com.docker.docker_1": {"/Applications/Docker.app/Contents/MacOS/uninstall": []},
    # The Homebrew prefix itself is out of scope; only its sub-directories are listed.
    "development.homebrew": {"/opt/homebrew": [], "/usr/local/Homebrew": []},
    "problematic_apps.homebrew": {"/opt/homebrew": [], "/usr/local/Homebrew": []},
    "database_servers.mongodb_mongod": {
        "/data/": [], "/journal/": [],  # duplicated by the absolute var/mongodb paths
        "/mongodb/mongod.log": ["/usr/local/var/log/mongodb/mongod.log",
                                "/opt/homebrew/var/log/mongodb/mongod.log"],
    },
}

# Applied to every entry.
GLOBAL_PATH_FIXES: dict[str, list[str]] = {
    "<USER_LIB>/Application": [],  # truncated string, present in 22 entries
    "<SYS_LIB>/Application": [],
    "<SYS_LIB>/SystemExtensions": [],  # OS-owned directory, not an app residual
    "<SYS_LIB>/StagedExtensions": [],
}

PLACEHOLDER_FIXES = [
    (r"\[account_id\]", "*"),
    (r"\$\(TeamID\)\.", "*."),
    (r"<VAR_FOLDERS>/xx/yyyyyy/", "<VAR_FOLDERS>/*/*/"),
]

# ---------------------------------------------------------------------------
# 2. Key normalisation.
# ---------------------------------------------------------------------------

# Entries whose key is a pseudo-id but which really are apps matched by a bundle-id family.
PSEUDO_TO_APP: dict[str, tuple[str, list[str], list[str]]] = {
    # pseudo key -> (primary key, bundle_ids, bundle_id_prefixes)
    "development.jetbrains_ides_intellij_idea_pycharm_webstorm_clion_goland_rider_datagrip_rubymine_phpstorm_appcode":
        ("com.jetbrains", [], ["com.jetbrains."]),
    "problematic_apps.jetbrains_ides_intellij_pycharm_webstorm_etc":
        ("com.jetbrains", [], ["com.jetbrains."]),
    "utilities.cleanmymac_x": ("com.macpaw.cleanmymac", [], ["com.macpaw.cleanmymac"]),
    "media_and_creative_tools.topaz_labs_suite_photo_ai_video_ai":
        ("com.topazlabs", [], ["com.topazlabs."]),
    "media_and_creative_tools.native_instruments_kontakt_maschine":
        ("com.native-instruments", [], ["com.native-instruments."]),
}

# Non-app entries: CLI toolchains, SDKs, servers, system caches. pseudo key -> slug.
TOOLCHAIN_SLUGS: dict[str, str] = {
    "development.colima": "colima",
    "development.lima": "lima",
    "development.flutter": "flutter",
    "development.react_native_expo": "react_native_expo",
    "development.aws_cli_aws_sam": "aws_cli",
    "development.google_cloud_sdk_gcloud": "gcloud",
    "development.azure_cli": "azure_cli",
    "development.terraform": "terraform",
    "development.pulumi": "pulumi",
    "development.ansible": "ansible",
    "development.kubernetes_kubectl_minikube_kind_k3d": "kubernetes",
    "development.homebrew": "homebrew",
    "problematic_apps.homebrew": "homebrew",
    "development.node_js_npm_nvm_fnm_pnpm_yarn_bun": "node",
    "development.python_system_pyenv_conda_pip_poetry_pipenv": "python",
    "development.rust_rustup_cargo": "rust",
    "development.go_golang": "go",
    "development.ruby_rbenv_rvm_ruby_build_bundler_gem": "ruby",
    "development.java_jdk_maven_gradle_intellij": "java",
    "development.swift_toolchain_non_xcode": "swift_toolchain",
    "development.dart_flutter_standalone": "dart",
    "development.cmake": "cmake",
    "development.meson": "meson",
    "development.bazel": "bazel",
    "development.buck2": "buck2",
    "development.xcodebuild_xcrun": "xcodebuild",
    "development.ngrok": "ngrok",
    "development.cloudflare_tunnel_cloudflared": "cloudflared",
    "development.github_codespaces_vs_code_extension": "github_codespaces",
    "development.tmate": "tmate",
    "development.localtunnel_lt": "localtunnel",
    "development.playwright_puppeteer_headless_browsers": "playwright",
    "development.neovim_modern_configurations_lazyvim_lunarvim_mason": "neovim",
    "development.serverless_cloud_clis_vercel_netlify_supabase": "serverless_clis",
    "utilities.wasmtime_wasmer_webassembly_runtimes": "wasm_runtimes",
    "database_servers.mysql_mariadb_homebrew": "mysql",
    "database_servers.mongodb_mongod": "mongodb",
    "database_servers.redis_homebrew": "redis",
    "macos_system_caches.macos_system_caches": "macos_system_caches",
    "ai_tools.hugging_face_cache_models_datasets": "hugging_face",
    "ai_tools.pytorch_torchvision_keras_caches": "pytorch",
    "ai_tools.local_vector_databases_chromadb_faiss": "vector_databases",
    "ai_tools.stable_diffusion_ui_caches_automatic1111_comfyui": "stable_diffusion",
    "ai_tools.weights_biases_wandb": "wandb",
    "ai_tools.github_copilot_tabnine_pieces_ai_assistants": "ai_assistants",
    "ai_tools.gradio_streamlit_ui_frameworks_cache": "gradio_streamlit",
    "ai_tools.llama_cpp_llamafile": "llama_cpp",
    "runtimes_and_package_managers.bun": "bun",
    "runtimes_and_package_managers.deno": "deno",
    "runtimes_and_package_managers.pnpm": "pnpm",
    "runtimes_and_package_managers.yarn": "yarn",
    "runtimes_and_package_managers.asdf_version_manager": "asdf",
    "runtimes_and_package_managers.nvm_node_version_manager": "nvm",
    "runtimes_and_package_managers.cargo_rustup": "cargo",
    "runtimes_and_package_managers.composer_php": "composer",
    "runtimes_and_package_managers.nuget_net": "nuget",
    "runtimes_and_package_managers.platformio_embedded_development": "platformio",
    "runtimes_and_package_managers.carthage_ios_dependency_manager": "carthage",
    "ai_agents_and_coding.aider_ai_pair_programmer": "aider",
    "ai_agents_and_coding.openhands_opendevin_autonomous_ai_software_engineer": "openhands",
    "ai_agents_and_coding.cline_roo_code_vs_code_ai_agents": "cline_roo",
    "data_science_and_ml_tools.kaggle_cli_api": "kaggle",
    "data_science_and_ml_tools.duckdb_local_analytical_db": "duckdb",
    "devops_and_build_tools.turborepo_global_cache": "turborepo",
    "devops_and_build_tools.nix_package_manager": "nix",
    "devops_and_build_tools.fly_io_flyctl": "flyctl",
    "web3_and_crypto.foundry_ethereum_development": "foundry",
    "web3_and_crypto.hardhat": "hardhat",
}

# Entries that merged unrelated vendors: split back, routing each path by its marker.
# source key -> [(primary id, bundle_ids, path markers)]
SPLIT_ENTRIES: dict[str, list[tuple[str, list[str], list[str], str]]] = {
    "com.hegenberg.BetterSnapTool / com.crowdcafe.windowmagnet": [
        ("com.hegenberg.BetterSnapTool", ["com.hegenberg.BetterSnapTool"],
         ["bettersnaptool", "hegenberg"], "BetterSnapTool"),
        ("com.crowdcafe.windowmagnet", ["com.crowdcafe.windowmagnet"],
         ["windowmagnet", "magnet"], "Magnet"),
    ],
    "com.apple.TV / com.apple.QuickTimePlayerX": [
        ("com.apple.TV", ["com.apple.TV"], ["com.apple.tv"], "Apple TV"),
        ("com.apple.QuickTimePlayerX", ["com.apple.QuickTimePlayerX"], ["quicktime"], "QuickTime Player"),
    ],
    "com.adobe.Photoshop / com.adobe.Illustrator / com.adobe.PremierePro": [
        ("com.adobe.Photoshop", ["com.adobe.Photoshop"], ["photoshop"], "Adobe Photoshop"),
        ("com.adobe.Illustrator", ["com.adobe.Illustrator"], ["illustrator"], "Adobe Illustrator"),
        ("com.adobe.PremierePro", ["com.adobe.PremierePro"], ["premiere"], "Adobe Premiere Pro"),
    ],
    # ExpressVPN contributed no dedicated paths — everything here is NordVPN's.
    "com.nordvpn.macos / com.expressvpn.ExpressVPN": [
        ("com.nordvpn.macos", ["com.nordvpn.macos"], [], "NordVPN"),
    ],
}

# Entries left in the catch-all "problematic_apps" bucket get a real category.
CATEGORY_OVERRIDES: dict[str, str] = {
    "com.adobe.ccx.process": "media_and_creative_tools",
    "com.adobe.Photoshop": "media_and_creative_tools",
    "com.adobe.Illustrator": "media_and_creative_tools",
    "com.adobe.PremierePro": "media_and_creative_tools",
    "com.blackmagic-design.DaVinciResolve": "media_and_creative_tools",
    "com.epicgames.EpicGamesLauncher": "game_clients",
    "com.valvesoftware.steam": "game_clients",
    "com.microsoft.word": "modern_productivity",
    "com.nordvpn.macos": "security_tools",
    "com.unity3d.unityhub": "development",
}

# Extra bundle-id prefixes for existing app entries.
EXTRA_PREFIXES: dict[str, list[str]] = {
    "com.unity3d.unityhub / com.unity3d.UnityEditor5.x": ["com.unity3d."],
    "com.adobe.Photoshop / com.adobe.Illustrator / com.adobe.PremierePro": [],
    "com.google.Chrome": ["com.google.chrome."],
    "com.microsoft.edgemac": ["com.microsoft.edgemac."],
    "com.brave.Browser": ["com.brave.browser."],
}

# Apps present in KnownResidualCatalog.swift but absent from the JSON base.
ADDITIONS: dict[str, dict] = {
    "com.google.antigravity-ide": {
        "name": "Antigravity IDE",
        "difficulty": "medium",
        "known_issues": [
            "Antigravity IDE — VS Code fork, keeps agent state in ~/.antigravity",
            "Electron/Chromium caches — GPUCache, Code Cache",
        ],
        "category": "ai_agents_and_coding",
        "paths": [
            "<HOME>/.antigravity",
            "<HOME>/.antigravity-ide",
            "<APP_SUPPORT>/Antigravity IDE",
            "<APP_SUPPORT>/com.google.antigravity-ide",
            "<CACHES>/com.google.antigravity-ide",
            "<CACHES>/com.google.antigravity-ide.ShipIt",
            "<USER_LIB>/HTTPStorages/com.google.antigravity-ide",
            "<LOGS>/Antigravity IDE",
            "<PREFS>/com.google.antigravity-ide*.plist",
            "<SAVED_STATE>/com.google.antigravity-ide.savedState",
        ],
    },
    "ai.opencode.desktop": {
        "name": "OpenCode",
        "difficulty": "medium",
        "known_issues": [
            "OpenCode — Electron app, keeps session history and model caches",
        ],
        "category": "ai_agents_and_coding",
        "paths": [
            "<APP_SUPPORT>/ai.opencode.desktop",
            "<CACHES>/ai.opencode.desktop",
            "<CACHES>/ai.opencode.desktop.ShipIt",
            "<USER_LIB>/HTTPStorages/ai.opencode.desktop",
            "<PREFS>/ai.opencode.desktop*.plist",
            "<SAVED_STATE>/ai.opencode.desktop.savedState",
        ],
    },
}

# ---------------------------------------------------------------------------
# 3. Purpose classification.
# ---------------------------------------------------------------------------

CACHE_TOKENS = {"CACHES", "USER_CACHE", "LOGS", "SAVED_STATE", "VAR_FOLDERS", "SYS_CACHES", "SYS_LOGS"}
CACHE_NAME_RE = re.compile(
    r"(^|[^a-z])(cache|caches|cache2|cachedata|_cacache|codecache|gpucache|shadercache|"
    r"grshadercache|crashpad|crashreporter|service worker|serviceworker|startupcache|"
    r"thumbnails|derivedData|logs|log|tmp|temp|diagnosticreports|media_cache|content_cache|"
    r"shadercaches|indexcache|scriptcache)([^a-z]|$)",
    re.IGNORECASE,
)

# Components shared with other products — never removed automatically.
SHARED_SUBSTRINGS = (
    "googlesoftwareupdate", "keystone", "googleupdater",
    "microsoft autoupdate", "com.microsoft.autoupdate", "com.microsoft.office.licensing",
    "adobe/adobegcclient", "adobe application manager", "adobe installers",
    "/internet plug-ins", "/input methods", "/quicklook", "/preferencepanes",
    "/spotlight", "/audio/plug-ins", "/systemextensions", "/stagedextensions",
    "/developer/commandlinetools", "/developer/toolchains",
    "javavirtualmachines", "/library/java",
)

# Shared developer toolchains: matched as whole paths or parents, never as substrings
# (".android" must not match "com.google.android.studio.plist").
SHARED_ROOTS = (
    "<home>/.gradle", "<home>/.android", "<home>/.m2", "<home>/.cocoapods",
    "<home>/library/android", "<home>/.sdkman", "<home>/.nuget",
)

USER_CONTENT_ROOTS = (
    "<home>/desktop", "<home>/documents", "<home>/downloads", "<home>/movies",
    "<home>/music", "<home>/pictures", "<home>/dropbox", "<home>/google drive",
    "<home>/onedrive", "<home>/creative cloud files", "<home>/parallels",
    "<home>/documents/parallels", "<home>/documents/virtual machines",
    "<home>/documents/virtual machines.localized", "<home>/documents/zoom",
    "<home>/library/cloudstorage", "<home>/library/mobile documents",
)


def strip_trailing(path: str) -> str:
    return path.rstrip("/") if path != "/" else path


def token_of(path: str) -> str | None:
    m = re.match(r"<([A-Z_]+)>", path)
    return m.group(1) if m else None


def classify(path: str) -> tuple[str, bool]:
    """Returns (purpose, requires_admin)."""
    token = token_of(path)
    lower = path.lower()
    is_system = token in SYSTEM_TOKENS or (token is None and path.startswith("/"))

    if any(lower == root or lower.startswith(root + "/") for root in USER_CONTENT_ROOTS):
        return "user_content", is_system
    if any(marker in lower for marker in SHARED_SUBSTRINGS):
        return "shared", is_system
    if any(lower == root or lower.startswith(root + "/") for root in SHARED_ROOTS):
        return "shared", is_system
    if token in CACHE_TOKENS:
        return "cache", is_system
    if CACHE_NAME_RE.search(path):
        return "cache", is_system
    return "app_data", is_system


def is_glob(path: str) -> bool:
    return any(ch in path for ch in "*?")


# ---------------------------------------------------------------------------
# 4. parent_suite.
# ---------------------------------------------------------------------------

SUITE_RULES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^com\.adobe\.", re.I), "Adobe Creative Cloud"),
    (re.compile(r"^com\.microsoft\.(word|excel|powerpoint|outlook|onenote|teams)", re.I), "Microsoft Office"),
    (re.compile(r"^com\.microsoft\.edgemac\.", re.I), "Microsoft Edge"),
    (re.compile(r"^com\.google\.chrome\.", re.I), "Google Chrome"),
    (re.compile(r"^com\.brave\.browser\.", re.I), "Brave Browser"),
    (re.compile(r"^org\.mozilla\.(firefox_esr|firefoxdeveloperedition|nightly)", re.I), "Mozilla Firefox"),
    (re.compile(r"^com\.operasoftware\.opera(gx|developeredition)", re.I), "Opera"),
    (re.compile(r"^com\.jetbrains", re.I), "JetBrains Toolbox"),
    (re.compile(r"^com\.unity3d", re.I), "Unity"),
    (re.compile(r"^com\.apple\.(dt\.|iphonesimulator)", re.I), "Xcode"),
    (re.compile(r"^com\.apple\.(logic10|FinalCut|Motion|Compressor|MainStage)", re.I), "Apple Pro Apps"),
]

TOOLCHAIN_SUITES = {
    "mysql": "Homebrew", "mongodb": "Homebrew", "redis": "Homebrew", "homebrew": "Homebrew",
    "xcodebuild": "Xcode", "swift_toolchain": "Xcode",
    "cargo": "Rust", "rust": "Rust",
    "nvm": "Node.js", "pnpm": "Node.js", "yarn": "Node.js", "bun": "Node.js", "node": "Node.js",
    "deno": "Node.js", "turborepo": "Node.js", "playwright": "Node.js",
    "dart": "Flutter", "flutter": "Flutter", "react_native_expo": "React Native",
    "hugging_face": "AI Models", "pytorch": "AI Models", "llama_cpp": "AI Models",
    "stable_diffusion": "AI Models", "wandb": "AI Models", "vector_databases": "AI Models",
    "gradio_streamlit": "AI Models", "kaggle": "AI Models",
    "aider": "AI Agents", "openhands": "AI Agents", "cline_roo": "AI Agents", "ai_assistants": "AI Agents",
    "duckdb": "Data Science",
    "colima": "Containers", "lima": "Containers", "kubernetes": "Kubernetes",
    "aws_cli": "Cloud CLIs", "azure_cli": "Cloud CLIs", "gcloud": "Cloud CLIs",
    "flyctl": "Cloud CLIs", "serverless_clis": "Cloud CLIs",
    "pulumi": "Infrastructure as Code", "terraform": "Infrastructure as Code", "ansible": "Infrastructure as Code",
    "bazel": "Build Tools", "buck2": "Build Tools", "cmake": "Build Tools", "meson": "Build Tools",
    "nix": "Package Managers", "asdf": "Version Managers",
    "python": "Python", "go": "Go", "ruby": "Ruby", "java": "Java",
    "composer": "PHP", "nuget": ".NET",
    "foundry": "Web3", "hardhat": "Web3",
    "macos_system_caches": "macOS",
    "ngrok": "Networking", "cloudflared": "Networking", "tmate": "Networking",
    "carthage": "iOS Development", "platformio": "Embedded",
    "neovim": "Neovim", "github_codespaces": "VS Code", "wasm_runtimes": "WebAssembly",
}


def suite_for_app(primary: str, bundle_ids: list[str]) -> str | None:
    for candidate in [primary, *bundle_ids]:
        for pattern, suite in SUITE_RULES:
            if pattern.match(candidate):
                if suite == "Xcode" and candidate.lower() == "com.apple.dt.xcode":
                    return None
                return suite
    return None


# ---------------------------------------------------------------------------
# 5. Migration.
# ---------------------------------------------------------------------------

def normalise_paths(key: str, entry: dict) -> list[dict]:
    fixes = PATH_FIXES.get(key, {})
    raw: list[str] = []
    for field in ("exact_paths", "glob_paths", "system_paths"):
        raw.extend(entry.get(field, []))

    expanded: list[str] = []
    for path in raw:
        # Lookups accept both the raw form and the form without a trailing slash.
        variants = [path, strip_trailing(path)]
        fix = next((fixes[v] for v in variants if v in fixes), None)
        if fix is None:
            fix = next((GLOBAL_PATH_FIXES[v] for v in variants if v in GLOBAL_PATH_FIXES), None)
        if fix is not None:
            expanded.extend(fix)
            continue
        for pattern, replacement in PLACEHOLDER_FIXES:
            path = re.sub(pattern, replacement, path)
        expanded.append(path)

    result: "OrderedDict[str, dict]" = OrderedDict()
    for path in expanded:
        path = strip_trailing(path)
        if not path:
            continue
        purpose, admin = classify(path)
        record = {"p": path, "purpose": purpose}
        if is_glob(path):
            record["glob"] = True
        if admin:
            record["system"] = True
        # Same path may arrive from several source fields.
        result.setdefault(path, record)
    return list(result.values())


def collapse(paths: list[dict]) -> list[dict]:
    """Drops a path when a non-glob ancestor of the same purpose is present."""
    ancestors = {p["p"] for p in paths if not p.get("glob")}
    kept = []
    for record in paths:
        path = record["p"]
        redundant = False
        parts = path.split("/")
        for i in range(1, len(parts)):
            parent = "/".join(parts[:i])
            if parent in ancestors and parent != path:
                parent_record = next(p for p in paths if p["p"] == parent)
                if parent_record["purpose"] == record["purpose"]:
                    redundant = True
                    break
        if not redundant:
            kept.append(record)
    return kept


def merge_issues(base: list[str], extra: list[str]) -> list[str]:
    """Keeps extra issues that are not a shortened restatement of an existing one."""
    merged = list(base)
    for issue in extra:
        head = issue.split("—")[0].strip().lower()
        if any(head and head in existing.lower() for existing in merged):
            continue
        if issue in merged:
            continue
        merged.append(issue)
    return merged


def main() -> int:
    engine = json.loads(ENGINE.read_text())
    ui = json.loads(UI.read_text())
    src_apps: dict[str, dict] = engine["apps"]
    src_ui: dict[str, dict] = ui["apps"]

    apps: "OrderedDict[str, dict]" = OrderedDict()
    toolchains: "OrderedDict[str, dict]" = OrderedDict()
    ui_apps: "OrderedDict[str, dict]" = OrderedDict()
    ui_toolchains: "OrderedDict[str, dict]" = OrderedDict()

    def target_of(key: str) -> tuple[str, str, list[str], list[str]]:
        """Returns (kind, primary key, bundle_ids, prefixes)."""
        if key in TOOLCHAIN_SLUGS:
            return "toolchain", TOOLCHAIN_SLUGS[key], [], []
        if key in PSEUDO_TO_APP:
            primary, ids, prefixes = PSEUDO_TO_APP[key]
            return "app", primary, ids, prefixes
        base = key[:-2] if key.endswith("_1") else key
        ids = [part.strip() for part in base.split(" / ") if part.strip()]
        primary = ids[0]
        return "app", primary, ids, EXTRA_PREFIXES.get(key, [])

    def targets_for(key: str, entry: dict, meta: dict):
        """Yields (kind, primary, ids, prefixes, paths, meta, category) per source entry."""
        paths = normalise_paths(key, entry)
        category = entry["category"]
        if key in SPLIT_ENTRIES:
            splits = SPLIT_ENTRIES[key]
            for primary, ids, markers, name in splits:
                own = [p for p in paths if any(m in p["p"].lower() for m in markers)]
                generic = [
                    p for p in paths
                    if not any(
                        any(m in p["p"].lower() for m in other_markers)
                        for _, _, other_markers, _ in splits
                    )
                ]
                split_meta = dict(meta)
                split_meta["name"] = name
                yield "app", primary, ids, [], own + generic, split_meta, category
            return
        kind, primary, ids, prefixes = target_of(key)
        yield kind, primary, ids, prefixes, paths, meta, category

    entries = [
        target
        for src_key, src_entry in src_apps.items()
        for target in targets_for(src_key, src_entry, src_ui.get(src_key, {}))
    ]

    for kind, primary, ids, prefixes, paths, meta, category in entries:
        if kind == "toolchain":
            bucket, ui_bucket = toolchains, ui_toolchains
            record = bucket.setdefault(primary, {"category": category, "paths": []})
            record["paths"].extend(paths)
        else:
            bucket, ui_bucket = apps, ui_apps
            record = bucket.setdefault(
                primary,
                {"bundle_ids": [], "bundle_id_prefixes": [], "category": category, "paths": []},
            )
            for bundle_id in ids:
                if bundle_id not in record["bundle_ids"]:
                    record["bundle_ids"].append(bundle_id)
            for prefix in prefixes:
                prefix = prefix.lower()
                if prefix not in record["bundle_id_prefixes"]:
                    record["bundle_id_prefixes"].append(prefix)
            record["paths"].extend(paths)
            # A specific category beats the generic "problematic_apps" bucket.
            if record["category"] == "problematic_apps" and category != "problematic_apps":
                record["category"] = category
            record["category"] = CATEGORY_OVERRIDES.get(primary, record["category"])

        ui_record = ui_bucket.get(primary)
        if ui_record is None:
            ui_bucket[primary] = {
                "name": meta.get("name", primary),
                "difficulty": meta.get("difficulty", "medium"),
                "known_issues": list(meta.get("known_issues", [])),
            }
        else:
            order = ["low", "medium", "high", "critical"]
            incoming = meta.get("difficulty", "medium")
            if order.index(incoming) > order.index(ui_record["difficulty"]):
                ui_record["difficulty"] = incoming
            ui_record["known_issues"] = merge_issues(
                ui_record["known_issues"], meta.get("known_issues", [])
            )
            # Prefer the more descriptive name.
            if len(meta.get("name", "")) > len(ui_record["name"]):
                ui_record["name"] = meta["name"]

    # Deduplicate + collapse, then sort deterministically.
    for bucket in (apps, toolchains):
        for key, record in bucket.items():
            unique: "OrderedDict[str, dict]" = OrderedDict()
            for path in record["paths"]:
                unique.setdefault(path["p"], path)
            record["paths"] = sorted(collapse(list(unique.values())), key=lambda p: p["p"])

    for key, addition in ADDITIONS.items():
        records = []
        for path in addition["paths"]:
            purpose, admin = classify(path)
            record = {"p": path, "purpose": purpose}
            if is_glob(path):
                record["glob"] = True
            if admin:
                record["system"] = True
            records.append(record)
        apps[key] = {
            "bundle_ids": [key],
            "bundle_id_prefixes": [],
            "category": addition["category"],
            "paths": sorted(collapse(records), key=lambda p: p["p"]),
        }
        ui_apps[key] = {
            "name": addition["name"],
            "difficulty": addition["difficulty"],
            "known_issues": list(addition["known_issues"]),
        }

    # Entries without a single path carry no information.
    for bucket, ui_bucket in ((apps, ui_apps), (toolchains, ui_toolchains)):
        for key in [k for k, v in bucket.items() if not v["paths"]]:
            del bucket[key]
            ui_bucket.pop(key, None)

    for key, record in apps.items():
        meta = ui_apps[key]
        meta["bundle_ids"] = record["bundle_ids"]
        meta["bundle_id_prefixes"] = record["bundle_id_prefixes"]
        suite = suite_for_app(key, record["bundle_ids"])
        if suite:
            meta["parent_suite"] = suite
    for key, meta in ui_toolchains.items():
        suite = TOOLCHAIN_SUITES.get(key)
        if suite:
            meta["parent_suite"] = suite

    engine_out = {
        "version": "3.0",
        "apps": OrderedDict(sorted(apps.items(), key=lambda kv: kv[0].lower())),
        "toolchains": OrderedDict(sorted(toolchains.items(), key=lambda kv: kv[0])),
    }
    ui_out = {
        "version": "3.0",
        "apps": OrderedDict(sorted(ui_apps.items(), key=lambda kv: kv[0].lower())),
        "toolchains": OrderedDict(sorted(ui_toolchains.items(), key=lambda kv: kv[0])),
    }

    problems = validate(engine_out, ui_out)
    if problems:
        for problem in problems[:60]:
            print("INVALID:", problem, file=sys.stderr)
        print(f"{len(problems)} problem(s); nothing written", file=sys.stderr)
        return 1

    ENGINE.write_text(json.dumps(engine_out, indent=2, ensure_ascii=False) + "\n")
    UI.write_text(json.dumps(ui_out, indent=2, ensure_ascii=False) + "\n")

    total_paths = sum(len(r["paths"]) for r in apps.values()) + \
        sum(len(r["paths"]) for r in toolchains.values())
    print(f"apps: {len(src_apps)} -> {len(apps)} + {len(toolchains)} toolchains")
    print(f"paths: {total_paths}")
    return 0


BUNDLE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*(\.[A-Za-z0-9_@-]+)+$")


def validate(engine: dict, ui: dict) -> list[str]:
    problems: list[str] = []
    for key, entry in engine["apps"].items():
        matchers = [m.lower() for m in entry["bundle_ids"]]
        prefixes = [p.rstrip(".").lower() for p in entry["bundle_id_prefixes"]]
        if not BUNDLE_ID_RE.match(key):
            problems.append(f"{key}: key is not bundle-id shaped")
        if key.lower() not in matchers and key.lower() not in prefixes:
            problems.append(f"{key}: key absent from bundle_ids/bundle_id_prefixes")
        if not entry["bundle_ids"] and not entry["bundle_id_prefixes"]:
            problems.append(f"{key}: no matchers")
        if key not in ui["apps"]:
            problems.append(f"{key}: missing ui_metadata")
    for key in ui["apps"]:
        if key not in engine["apps"]:
            problems.append(f"{key}: ui_metadata without engine entry")
    for key in engine["toolchains"]:
        if key not in ui["toolchains"]:
            problems.append(f"toolchain {key}: missing ui_metadata")

    for section in ("apps", "toolchains"):
        for key, entry in engine[section].items():
            seen = set()
            for record in entry["paths"]:
                path = record["p"]
                if path in seen:
                    problems.append(f"{key}: duplicate path {path}")
                seen.add(path)
                if record["purpose"] not in ("cache", "app_data", "shared", "user_content"):
                    problems.append(f"{key}: bad purpose {record['purpose']} for {path}")
                token = token_of(path)
                if token is None:
                    if not path.startswith(ABSOLUTE_ALLOWED):
                        problems.append(f"{key}: untokenised path {path}")
                    elif path.strip("/").count("/") == 0:
                        problems.append(f"{key}: root-level path {path}")
                elif token not in TOKENS:
                    problems.append(f"{key}: unknown token in {path}")
                if is_glob(path) != bool(record.get("glob")):
                    problems.append(f"{key}: glob flag mismatch for {path}")
                if re.search(r"\[|\]|\$\(|~\d|[^\x00-\x7F]", path):
                    problems.append(f"{key}: placeholder or non-ascii in {path}")
                if path.endswith("/"):
                    problems.append(f"{key}: trailing slash in {path}")
    return problems


if __name__ == "__main__":
    sys.exit(main())
