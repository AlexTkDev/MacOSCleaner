#!/usr/bin/env python3
"""Validates engine_paths.json / ui_metadata.json (schema v3).

Run from the repository root:  python3 scripts/validate_engine_paths.py
Exit code 1 means the data must not be shipped.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from migrate_engine_paths_v3 import ENGINE, UI, validate  # noqa: E402

# Paths that must never be classified as a cache: regular cleanup would delete them.
USER_DATA_RE = re.compile(
    r"login data|cookies|bookmarks|places\.sqlite|logins\.json|key4\.db|web data|"
    r"secure preferences|local state|/documents/|/desktop/|/saves|keychain",
    re.IGNORECASE,
)

USER_CONTENT_ROOTS = (
    "<HOME>/Desktop",
    "<HOME>/Documents",
    "<HOME>/Downloads",
    "<HOME>/Movies",
    "<HOME>/Music",
    "<HOME>/Pictures",
    "<HOME>/Dropbox",
    "<HOME>/Google Drive",
    "<HOME>/OneDrive",
    "<HOME>/Creative Cloud Files",
    "<HOME>/Parallels",
    "<HOME>/Documents/Parallels",
    "<HOME>/Documents/Virtual Machines",
    "<HOME>/Documents/Virtual Machines.localized",
    "<HOME>/Documents/Zoom",
    "<HOME>/Library/CloudStorage",
    "<HOME>/Library/Mobile Documents",
    # Models / global package stores — informational, never unattended cleanup
    "<HOME>/.ollama",
    "<HOME>/.pub-cache",
    "<HOME>/.cache/huggingface",
    "<HOME>/.cache/torch",
    "<HOME>/.cache/whisper",
    "<HOME>/.cache/mlx",
    "<HOME>/.cache/vllm",
    "<HOME>/.cache/kagglehub",
    "<USER_CACHE>/huggingface",
    "<CACHES>/huggingface",
    "<APP_SUPPORT>/LM Studio",
    "<APP_SUPPORT>/Jan",
    "<APP_SUPPORT>/jan.ai.app",
    "<HOME>/jan",
    "<USER_CACHE>/lm-studio",
)


def _under_root(path: str, root: str) -> bool:
    return path == root or path.startswith(root + "/")


def main() -> int:
    engine = json.loads(ENGINE.read_text())
    ui = json.loads(UI.read_text())

    problems = validate(engine, ui)

    if engine.get("version") != "3.0" or ui.get("version") != "3.0":
        problems.append("version must be 3.0 in both files")

    for section in ("apps", "toolchains"):
        for key, entry in engine[section].items():
            for record in entry["paths"]:
                path = record["p"]
                purpose = record["purpose"]
                if path == "<HOME>":
                    problems.append(f"{key}: bare home token must not be classified: {path}")
                if purpose == "app_data" and any(_under_root(path, root) for root in USER_CONTENT_ROOTS):
                    problems.append(f"{key}: user content under personal roots must be user_content: {path}")
                if purpose == "user_content" and not any(_under_root(path, root) for root in USER_CONTENT_ROOTS):
                    problems.append(f"{key}: user_content must stay under personal roots: {path}")
                if purpose == "cache" and USER_DATA_RE.search(path):
                    problems.append(f"{key}: user data classified as cache: {path}")
            if not entry["paths"]:
                problems.append(f"{key}: entry without paths")

    seen_ids: dict[str, str] = {}
    for key, entry in engine["apps"].items():
        for bundle_id in entry["bundle_ids"]:
            lower = bundle_id.lower()
            if lower in seen_ids:
                problems.append(f"{key}: bundle id {bundle_id} also claimed by {seen_ids[lower]}")
            seen_ids[lower] = key

    path_owners: dict[str, set[str]] = {}
    path_purposes: dict[str, set[str]] = {}
    for section in ("apps", "toolchains"):
        for key, entry in engine[section].items():
            for record in entry["paths"]:
                path = record["p"]
                path_owners.setdefault(path, set()).add(key)
                path_purposes.setdefault(path, set()).add(record["purpose"])

    for path, owners in path_owners.items():
        purposes = path_purposes[path]
        if len(owners) > 1 and len(purposes) > 1:
            problems.append(f"cross-entry path collision: {path} owned by {', '.join(sorted(owners))}")

    for problem in problems:
        print("INVALID:", problem, file=sys.stderr)
    if problems:
        print(f"{len(problems)} problem(s)", file=sys.stderr)
        return 1

    apps = engine["apps"]
    toolchains = engine["toolchains"]
    paths = sum(len(v["paths"]) for v in apps.values()) + \
        sum(len(v["paths"]) for v in toolchains.values())
    print(f"OK: {len(apps)} apps, {len(toolchains)} toolchains, {paths} paths")
    return 0


if __name__ == "__main__":
    sys.exit(main())
