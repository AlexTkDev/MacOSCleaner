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
from functools import cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "MacOSCleaner" / "Resources"
ENGINE = RESOURCES / "engine_paths.json"
UI = RESOURCES / "ui_metadata.json"

TOKENS = {
    "APP_SUPPORT", "CACHES", "PREFS", "CONTAINERS", "GROUP_CONTAINERS", "LOGS", "HOME",
    "SAVED_STATE", "USER_LIB", "USER_CONFIG", "USER_CACHE", "USER_LOCAL_SHARE",
    "USER_LOCAL_STATE", "VAR_FOLDERS",
    "SYS_LIB", "SYS_APP_SUPPORT", "SYS_LAUNCH_AGENTS", "SYS_LAUNCH_DAEMONS",
    "SYS_PRIV_HELPERS", "SYS_CACHES", "SYS_PREFS", "SYS_LOGS",
}
SYSTEM_TOKENS = {t for t in TOKENS if t.startswith("SYS_")}

# Absolute (non-token) prefixes allowed to stay in the base.
ABSOLUTE_ALLOWED = ("/usr/local/", "/opt/homebrew/", "/Library/", "/var/log/", "/var/root/")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from catalog_policy import POLICY, migrate_tables, user_content_roots  # noqa: E402


@cache
def _migrate() -> dict:
    return migrate_tables()


def _path_fixes() -> dict:
    return _migrate().get("path_fixes") or {}


def _global_path_fixes() -> dict:
    return _migrate().get("global_path_fixes") or {}


def _pseudo_to_app() -> dict[str, tuple[str, list[str], list[str]]]:
    raw = _migrate().get("pseudo_to_app") or {}
    out: dict[str, tuple[str, list[str], list[str]]] = {}
    for key, value in raw.items():
        out[key] = (value["primary"], list(value["bundle_ids"]), list(value["prefixes"]))
    return out


def _toolchain_slugs() -> dict[str, str]:
    return dict(_migrate().get("toolchain_slugs") or {})


def _split_entries() -> dict[str, list[tuple[str, list[str], list[str], str]]]:
    raw = _migrate().get("split_entries") or {}
    out: dict[str, list[tuple[str, list[str], list[str], str]]] = {}
    for key, rows in raw.items():
        out[key] = [
            (row["primary"], list(row["bundle_ids"]), list(row["markers"]), row["name"])
            for row in rows
        ]
    return out


def _category_overrides() -> dict[str, str]:
    return dict(_migrate().get("category_overrides") or {})


def _extra_prefixes() -> dict[str, list[str]]:
    return dict(_migrate().get("extra_prefixes") or {})


def _bundle_id_overrides() -> dict[str, str]:
    raw = _migrate().get("bundle_id_overrides") or {}
    return {str(k): str(v) for k, v in raw.items()}


def _bundle_id_additions() -> dict[str, list[str]]:
    raw = _migrate().get("bundle_id_additions") or {}
    out: dict[str, list[str]] = {}
    for key, ids in raw.items():
        out[str(key)] = [str(bundle_id) for bundle_id in ids]
    return out


def _additions() -> dict[str, dict]:
    return dict(_migrate().get("additions") or {})


def _toolchain_suites() -> dict[str, str]:
    return dict(_migrate().get("toolchain_suites") or {})


# Generic placeholder rewrites (not vendor leftovers).
PLACEHOLDER_FIXES = [
    (r"\[account_id\]", "*"),
    (r"\$\(TeamID\)\.", "*."),
    (r"<VAR_FOLDERS>/xx/yyyyyy/", "<VAR_FOLDERS>/*/*/"),
]

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

    if any(lower == root or lower.startswith(root + "/") for root in (r.lower() for r in user_content_roots())):
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


def suite_for_app(primary: str, bundle_ids: list[str]) -> str | None:
    for candidate in [primary, *bundle_ids]:
        for pattern, suite in SUITE_RULES:
            if pattern.match(candidate):
                if suite == "Xcode" and candidate.lower() == "com.apple.dt.xcode":
                    return None
                return suite
    return None


def merge_app_records(
    apps: "OrderedDict[str, dict]",
    ui_apps: "OrderedDict[str, dict]",
    source: str,
    target: str,
) -> None:
    if source == target or source not in apps:
        return
    source_record = apps.pop(source)
    source_meta = ui_apps.pop(source, {"name": source, "difficulty": "medium", "known_issues": []})
    target_record = apps.get(target)
    if target_record is None:
        apps[target] = source_record
        ui_apps[target] = source_meta
        return

    for bundle_id in source_record["bundle_ids"]:
        if bundle_id not in target_record["bundle_ids"]:
            target_record["bundle_ids"].append(bundle_id)
    for prefix in source_record["bundle_id_prefixes"]:
        if prefix not in target_record["bundle_id_prefixes"]:
            target_record["bundle_id_prefixes"].append(prefix)
    target_record["paths"].extend(source_record["paths"])
    if target_record["category"] == "problematic_apps" and source_record["category"] != "problematic_apps":
        target_record["category"] = source_record["category"]

    order = ["low", "medium", "high", "critical"]
    target_meta = ui_apps[target]
    source_difficulty = source_meta.get("difficulty", "medium")
    if order.index(source_difficulty) > order.index(target_meta.get("difficulty", "medium")):
        target_meta["difficulty"] = source_difficulty
    target_meta["known_issues"] = merge_issues(
        target_meta.get("known_issues", []),
        source_meta.get("known_issues", []),
    )
    if len(source_meta.get("name", "")) > len(target_meta.get("name", "")):
        target_meta["name"] = source_meta["name"]


# ---------------------------------------------------------------------------
# 5. Migration.
# ---------------------------------------------------------------------------

def normalise_paths(key: str, entry: dict) -> list[dict]:
    fixes = _path_fixes().get(key, {})
    raw: list[str] = []
    for field in ("exact_paths", "glob_paths", "system_paths"):
        raw.extend(entry.get(field, []))

    expanded: list[str] = []
    for path in raw:
        # Lookups accept both the raw form and the form without a trailing slash.
        variants = [path, strip_trailing(path)]
        fix = next((fixes[v] for v in variants if v in fixes), None)
        if fix is None:
            global_fixes = _global_path_fixes()
            fix = next((global_fixes[v] for v in variants if v in global_fixes), None)
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
    if not POLICY.is_file():
        print(f"missing {POLICY}", file=sys.stderr)
        return 1
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
        slugs = _toolchain_slugs()
        if key in slugs:
            return "toolchain", slugs[key], [], []
        pseudo = _pseudo_to_app()
        if key in pseudo:
            primary, ids, prefixes = pseudo[key]
            return "app", primary, ids, prefixes
        base = key[:-2] if key.endswith("_1") else key
        ids = [part.strip() for part in base.split(" / ") if part.strip()]
        primary = ids[0]
        return "app", primary, ids, _extra_prefixes().get(key, [])

    def targets_for(key: str, entry: dict, meta: dict):
        """Yields (kind, primary, ids, prefixes, paths, meta, category) per source entry."""
        paths = normalise_paths(key, entry)
        category = entry["category"]
        splits_map = _split_entries()
        if key in splits_map:
            splits = splits_map[key]
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
            record["category"] = _category_overrides().get(primary, record["category"])

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

    for key, addition in _additions().items():
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

    for source, target in _bundle_id_overrides().items():
        merge_app_records(apps, ui_apps, source, target)

    for key, ids in _bundle_id_additions().items():
        record = apps.get(key)
        if record is None:
            continue
        for bundle_id in ids:
            if bundle_id not in record["bundle_ids"]:
                record["bundle_ids"].append(bundle_id)

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
        suite = _toolchain_suites().get(key)
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
