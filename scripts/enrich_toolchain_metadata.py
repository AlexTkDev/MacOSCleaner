#!/usr/bin/env python3
"""Fill parent_suite and sparse known_issues for ui_metadata toolchains.

Tables live in gitignored catalog_policy.json.

Run from repo root:  python3 scripts/enrich_toolchain_metadata.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "MacOSCleaner" / "Resources" / "ui_metadata.json"

sys.path.insert(0, str(Path(__file__).resolve().parent))

from catalog_policy import POLICY, toolchain_issues_extra, toolchain_suites  # noqa: E402

MIN_ISSUES = 3


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
    if not POLICY.is_file():
        print(f"missing {POLICY}", file=sys.stderr)
        return 1

    ui = json.loads(UI.read_text())
    toolchains = ui.get("toolchains", {})
    if not toolchains:
        print("No toolchains section", file=sys.stderr)
        return 1

    suites = toolchain_suites()
    extras = toolchain_issues_extra()

    suites_added = issues_padded = 0
    for key, meta in toolchains.items():
        suite = suites.get(key)
        if suite and meta.get("parent_suite") != suite:
            meta["parent_suite"] = suite
            suites_added += 1
        issues = meta.get("known_issues", [])
        if len(issues) < MIN_ISSUES and key in extras:
            before = len(issues)
            meta["known_issues"] = merge_issues(issues, extras[key])
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
