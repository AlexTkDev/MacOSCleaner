#!/usr/bin/env python3
"""Load gitignored catalog_policy.json (local SoT sidecar).

Tracked scripts must not embed vendor leftover paths. Those live in:
  MacOSCleaner/Resources/engine_paths.json
  MacOSCleaner/Resources/ui_metadata.json
  MacOSCleaner/Resources/catalog_policy.json
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "MacOSCleaner" / "Resources"
POLICY = RESOURCES / "catalog_policy.json"

# Generic personal folders (macOS layout). Not a vendor leftover catalog.
PUBLIC_USER_CONTENT_ROOTS: tuple[str, ...] = (
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
)


def load() -> dict:
    if not POLICY.is_file():
        return {}
    return json.loads(POLICY.read_text())


def require() -> dict:
    if not POLICY.is_file():
        raise FileNotFoundError(
            f"missing {POLICY} — local sidecar next to engine_paths.json / ui_metadata.json"
        )
    return load()


def user_content_roots() -> tuple[str, ...]:
    roots = load().get("user_content_roots")
    if isinstance(roots, list) and roots:
        return tuple(str(r) for r in roots)
    return PUBLIC_USER_CONTENT_ROOTS


def toolchain_suites() -> dict[str, str]:
    raw = load().get("toolchain_suites") or {}
    return {str(k): str(v) for k, v in raw.items()}


def toolchain_issues_extra() -> dict[str, list[str]]:
    raw = load().get("toolchain_issues_extra") or {}
    return {str(k): [str(i) for i in v] for k, v in raw.items()}


def migrate_tables() -> dict:
    return dict(load().get("migrate") or {})
