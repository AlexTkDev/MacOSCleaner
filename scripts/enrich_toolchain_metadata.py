#!/usr/bin/env python3
"""Fill parent_suite and sparse known_issues for ui_metadata toolchains.

Run from repo root:  python3 scripts/enrich_toolchain_metadata.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "MacOSCleaner" / "Resources" / "ui_metadata.json"

TOOLCHAIN_SUITES: dict[str, str] = {
    "mysql": "Homebrew",
    "mongodb": "Homebrew",
    "redis": "Homebrew",
    "homebrew": "Homebrew",
    "xcodebuild": "Xcode",
    "swift_toolchain": "Xcode",
    "cargo": "Rust",
    "rust": "Rust",
    "nvm": "Node.js",
    "pnpm": "Node.js",
    "yarn": "Node.js",
    "bun": "Node.js",
    "node": "Node.js",
    "deno": "Node.js",
    "turborepo": "Node.js",
    "playwright": "Node.js",
    "dart": "Flutter",
    "flutter": "Flutter",
    "react_native_expo": "React Native",
    "hugging_face": "AI Models",
    "pytorch": "AI Models",
    "llama_cpp": "AI Models",
    "stable_diffusion": "AI Models",
    "wandb": "AI Models",
    "vector_databases": "AI Models",
    "gradio_streamlit": "AI Models",
    "kaggle": "AI Models",
    "aider": "AI Agents",
    "openhands": "AI Agents",
    "cline_roo": "AI Agents",
    "ai_assistants": "AI Agents",
    "duckdb": "Data Science",
    "colima": "Containers",
    "lima": "Containers",
    "kubernetes": "Kubernetes",
    "aws_cli": "Cloud CLIs",
    "azure_cli": "Cloud CLIs",
    "gcloud": "Cloud CLIs",
    "flyctl": "Cloud CLIs",
    "serverless_clis": "Cloud CLIs",
    "pulumi": "Infrastructure as Code",
    "terraform": "Infrastructure as Code",
    "ansible": "Infrastructure as Code",
    "bazel": "Build Tools",
    "buck2": "Build Tools",
    "cmake": "Build Tools",
    "meson": "Build Tools",
    "nix": "Package Managers",
    "asdf": "Version Managers",
    "python": "Python",
    "go": "Go",
    "ruby": "Ruby",
    "java": "Java",
    "composer": "PHP",
    "nuget": ".NET",
    "foundry": "Web3",
    "hardhat": "Web3",
    "macos_system_caches": "macOS",
    "ngrok": "Networking",
    "cloudflared": "Networking",
    "tmate": "Networking",
    "carthage": "iOS Development",
    "platformio": "Embedded",
    "neovim": "Neovim",
    "github_codespaces": "VS Code",
    "wasm_runtimes": "WebAssembly",
}

# Extra bullets appended when an entry has fewer than MIN_ISSUES items.
MIN_ISSUES = 3

TOOLCHAIN_ISSUES_EXTRA: dict[str, list[str]] = {
    "ai_assistants": [
        "GitHub Copilot — ~/.copilot, VS Code globalStorage",
        "Tabnine — ~/.tabnine, local snippet index",
        "Pieces — ~/Library/Application Support/com.pieces.*",
    ],
    "aider": [
        "~/.aider — config and session state",
        "~/.aider.tags.cache.v3 — tag index for edited files",
        "Project-root backups — .aider.chat.history.md in repos",
    ],
    "asdf": [
        "Multi-language version manager (Node, Ruby, Python, Elixir, …)",
        "~/.asdf — plugin shims and downloaded runtimes",
        "Uninstalling asdf does not remove language versions installed via plugins",
    ],
    "bun": [
        "~/.bun — runtime binaries and global package installs",
        "~/Library/Caches/bun — fetched package cache",
        "Bun lockfile projects may leave node_modules in repos separately",
    ],
    "buck2": [
        "~/.buckd — long-running build daemon",
        "~/.buck — local buck configuration",
        "Project buck-out/ dirs are handled by cleanProjectLocalBuildArtifacts",
    ],
    "carthage": [
        "~/Library/Caches/org.carthage.CarthageKit — downloaded XCFrameworks",
        "Carthage/Build inside iOS projects — not in this global cache entry",
        "Checkouts folder in project Carthage/ — project-local",
    ],
    "cline_roo": [
        "VS Code globalStorage — saoudrizwan.claude-dev (Cline)",
        "~/.cline — Roo Code / Cline agent state",
        "Context histories can reach tens of MB per workspace",
    ],
    "cloudflared": [
        "~/.cloudflared — tunnel credentials and config",
        "Tunnel certificates — *.json, *.pem in ~/.cloudflared",
        "Log files from active tunnels",
    ],
    "composer": [
        "~/.composer/cache — downloaded PHP packages",
        "Global vendor/ if composer global require was used",
        "auth.json — GitHub/ Packagist tokens in ~/.composer",
    ],
    "deno": [
        "~/.deno — Deno cache, deps, and installed tools",
        "~/Library/Caches/deno — additional fetch cache",
        "Deno compile artifacts in project dirs — project-local",
    ],
    "duckdb": [
        "~/.duckdb — extensions and local state",
        "~/.duckdb_history — SQL command history",
        "Large .duckdb database files in project folders — not global",
    ],
    "flyctl": [
        "~/.fly — auth tokens and app config",
        "Local Docker agent state for remote builds",
        "Build logs cached between deploy attempts",
    ],
    "foundry": [
        "~/.foundry — forge/cast/anvil caches and artifacts",
        "~/.svm — multiple solc compiler versions",
        "Project out/ and cache/ — project-local build dirs",
    ],
    "gradio_streamlit": [
        "~/.streamlit — Streamlit credentials and config",
        "~/Library/Caches/gradio — uploaded file temp cache",
        "~/Library/Caches/streamlit — session media cache",
    ],
    "hardhat": [
        "~/.hardhat — global Hardhat config and telemetry",
        "~/Library/Caches/hardhat-nodejs — compiler download cache",
        "Project artifacts/ and cache/ — project-local",
    ],
    "kaggle": [
        "~/.kaggle — API token (kaggle.json)",
        "~/Library/Caches/kaggle — downloaded dataset archives (10–50 GB common)",
        "Competition submissions cache",
    ],
    "llama_cpp": [
        "~/Library/Caches/llama.cpp — compiled objects and model fetch cache",
        "GGUF model files often stored separately in ~/models or project dirs",
        "make-based build trees in source checkouts — project-local",
    ],
    "meson": [
        "~/.local/share/meson — wrap subproject cache",
        "~/Library/Caches/meson — build system cache",
        "Project build/ dirs — project-local",
    ],
    "ngrok": [
        "~/.ngrok2 / ~/.ngrok3 — authtoken and tunnel config",
        "~/Library/Caches/ngrok — update and session cache",
        "~/.config/ngrok — additional config on newer installs",
    ],
    "nix": [
        "/nix/store — system volume (managed via nix-collect-garbage, not this app)",
        "~/.nix-profile — user profile symlinks",
        "~/.cache/nix — evaluation and download cache",
    ],
    "nuget": [
        "~/.nuget/packages — global package cache (several to dozens of GB)",
        "HTTP cache for package restore",
        "Project bin/ and obj/ — project-local",
    ],
    "nvm": [
        "~/.nvm — all installed Node.js versions (100–300 MB each)",
        "Default alias and .nvmrc resolution state",
        "npm global packages inside each nvm version directory",
    ],
    "openhands": [
        "~/.openhands / ~/.opendevin — agent workspace and logs",
        "Docker images pulled for sandboxed execution",
        "Command execution logs can reach gigabytes per session",
    ],
    "pnpm": [
        "~/.pnpm-store — content-addressable global store",
        "~/.local/share/pnpm — pnpm state and metadata",
        "Hard-linked node_modules in projects reference the global store",
    ],
    "pytorch": [
        "~/Library/Caches/torch — torchvision pretrained weights",
        "~/.keras — Keras datasets and model weights",
        "CUDA/MPS compiled kernels cached per PyTorch version",
    ],
    "redis": [
        "/opt/homebrew/var/db/redis — Homebrew Redis data (Apple Silicon)",
        "/usr/local/var/db/redis — Homebrew Redis data (Intel)",
        "dump.rdb and appendonly.aof — persistence files",
    ],
    "serverless_clis": [
        "~/.vercel / ~/.netlify / ~/.supabase — CLI auth and project links",
        "~/Library/Caches/vercel — build output cache",
        "Local dev database containers started by Supabase CLI",
    ],
    "stable_diffusion": [
        "~/Library/Caches/stable-diffusion — model and VAE cache",
        "~/Library/Caches/clip — CLIP encoder weights",
        "~/Library/Caches/xformers — attention kernel cache",
    ],
    "tmate": [
        "~/.tmate — SSH keys for shared sessions",
        "~/.tmate.conf — session configuration",
        "Read-only session logs",
    ],
    "turborepo": [
        "~/.turbo — global remote cache credentials",
        "~/Library/Caches/turbo — local build artifact cache (can reach dozens of GB)",
        "Monorepo .turbo/ dirs — project-local",
    ],
    "vector_databases": [
        "~/.chroma — ChromaDB persistent collections",
        "~/.faiss — FAISS index files from LangChain/LlamaIndex defaults",
        "Embeddings recreated on delete — safe to clear for orphaned agents",
    ],
    "wandb": [
        "~/Library/Caches/wandb — run logs before cloud sync",
        "~/.config/wandb — API key and settings",
        "~/.local/share/wandb — artifact staging",
    ],
    "wasm_runtimes": [
        "~/.wasmer — Wasmer compiler and module cache",
        "~/Library/Caches/wasmtime — Wasmtime JIT cache",
        "Compiled modules tied to specific wasmtime/wasmer versions",
    ],
    "yarn": [
        "~/.yarn — Berry (v2+) global cache and releases",
        "~/Library/Caches/yarn — Classic yarn fetch cache",
        "Zero-Install .pnp.cjs state in projects — project-local",
    ],
    "cargo": [
        "~/.cargo/registry — crates.io download cache",
        "~/.cargo/git — git dependency checkouts",
        "~/.rustup/downloads — toolchain installer cache",
    ],
}


def merge_issues(existing: list[str], extra: list[str]) -> list[str]:
    merged = list(existing)
    for issue in extra:
        head = issue.split("—")[0].strip().lower()
        if any(head and head in e.lower() for e in merged):
            continue
        if issue not in merged:
            merged.append(issue)
    return merged


def main() -> int:
    ui = json.loads(UI.read_text())
    toolchains = ui.get("toolchains", {})
    if not toolchains:
        print("No toolchains section", file=sys.stderr)
        return 1

    suites_added = issues_padded = 0
    for key, meta in toolchains.items():
        suite = TOOLCHAIN_SUITES.get(key)
        if suite and meta.get("parent_suite") != suite:
            meta["parent_suite"] = suite
            suites_added += 1
        issues = meta.get("known_issues", [])
        if len(issues) < MIN_ISSUES and key in TOOLCHAIN_ISSUES_EXTRA:
            before = len(issues)
            meta["known_issues"] = merge_issues(issues, TOOLCHAIN_ISSUES_EXTRA[key])
            if len(meta["known_issues"]) > before:
                issues_padded += 1

    missing_suite = [k for k, v in toolchains.items() if not v.get("parent_suite")]
    sparse = [k for k, v in toolchains.items() if len(v.get("known_issues", [])) < MIN_ISSUES]

    if missing_suite:
        for key in missing_suite:
            print(f"WARN: no parent_suite mapping for {key}", file=sys.stderr)
    if sparse:
        for key in sparse:
            print(f"WARN: fewer than {MIN_ISSUES} known_issues for {key}", file=sys.stderr)

    UI.write_text(json.dumps(ui, indent=2, ensure_ascii=False) + "\n")
    print(f"toolchains: {len(toolchains)}")
    print(f"parent_suite set/updated: {suites_added}")
    print(f"known_issues padded: {issues_padded}")
    print(f"remaining without suite: {len(missing_suite)}")
    print(f"remaining sparse issues: {len(sparse)}")
    return 1 if missing_suite or sparse else 0


if __name__ == "__main__":
    sys.exit(main())
